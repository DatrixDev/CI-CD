#!/bin/bash

TOKEN="$TELEGRAM_TOKEN"
ADMIN_CHAT_ID="$TELEGRAM_CHAT_ID"

BASE_DIR="/home/datrixdev/telegram-cicd-bot"
DATA_DIR="$BASE_DIR/data"

KNOWN_USERS="$DATA_DIR/known_users.txt"
MEMBERS="$DATA_DIR/members.txt"
PERMISSIONS="$DATA_DIR/permissions.txt"

mkdir -p "$DATA_DIR"
touch "$KNOWN_USERS" "$MEMBERS" "$PERMISSIONS"

OFFSET=0



send_message() {
    local CHAT_ID="$1"
    local TEXT="$2"

    curl -sS -X POST \
        "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${TEXT}" > /dev/null
}


send_keyboard() {
    local CHAT_ID="$1"
    local TEXT="$2"
    local KEYBOARD="$3"

    curl -sS -X POST \
        "https://api.telegram.org/bot${TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${TEXT}" \
        --data-urlencode "reply_markup=${KEYBOARD}" > /dev/null
}


answer_callback() {
    local CALLBACK_ID="$1"

    curl -sS -X POST \
        "https://api.telegram.org/bot${TOKEN}/answerCallbackQuery" \
        --data-urlencode "callback_query_id=${CALLBACK_ID}" > /dev/null
}




get_username() {
    local ID="$1"

    awk -F'|' -v id="$ID" \
        '$1 == id {print $2; exit}' "$KNOWN_USERS"
}


get_role() {
    local ID="$1"

    if [ "$ID" = "$ADMIN_CHAT_ID" ]; then
        echo "admin"
        return
    fi

    awk -F'|' -v id="$ID" \
        '$1 == id {print $3; exit}' "$MEMBERS"
}


is_member() {
    local ID="$1"

    if [ "$ID" = "$ADMIN_CHAT_ID" ]; then
        return 0
    fi

    grep -q "^${ID}|" "$MEMBERS"
}


has_permission() {
    local ID="$1"
    local CMD="$2"

    local ROLE
    local CUSTOM

    ROLE=$(get_role "$ID")

    if [ "$ROLE" = "admin" ]; then
        return 0
    fi


    CUSTOM=$(awk -F'|' \
        -v id="$ID" \
        -v cmd="$CMD" \
        '$1 == id && $2 == cmd {v=$3} END {print v}' \
        "$PERMISSIONS")

    if [ "$CUSTOM" = "allow" ]; then
        return 0
    fi

    if [ "$CUSTOM" = "deny" ]; then
        return 1
    fi

    if [ "$ROLE" = "operator" ]; then
        case "$CMD" in
            status|version|logs|uptime|resources|restarts|health|history)
                return 0
                ;;
        esac
    fi

    if [ "$ROLE" = "viewer" ]; then
        case "$CMD" in
            status|version|uptime|health)
                return 0
                ;;
        esac
    fi

    return 1
}




update_command_menu() {
    local CHAT_ID="$1"

    local COMMANDS='[]'

  
    if ! is_member "$CHAT_ID"; then

        COMMANDS=$(jq -nc '
        [
          {
            command:"start",
            description:"Đăng ký sử dụng bot"
          }
        ]')

    else

        COMMANDS=$(jq -nc '
        [
          {
            command:"help",
            description:"Xem các lệnh được phép sử dụng"
          }
        ]')

        if has_permission "$CHAT_ID" "status"; then
            COMMANDS=$(echo "$COMMANDS" | jq \
                '. + [{
                    command:"status",
                    description:"Xem trạng thái hệ thống"
                }]')
        fi

        if has_permission "$CHAT_ID" "version"; then
            COMMANDS=$(echo "$COMMANDS" | jq \
                '. + [{
                    command:"version",
                    description:"Xem phiên bản đang chạy"
                }]')
        fi

        if has_permission "$CHAT_ID" "logs"; then
            COMMANDS=$(echo "$COMMANDS" | jq \
                '. + [{
                    command:"logs",
                    description:"Xem nhật ký ứng dụng"
                }]')
        fi

        if has_permission "$CHAT_ID" "uptime"; then
            COMMANDS=$(echo "$COMMANDS" | jq \
                '. + [{
                    command:"uptime",
                    description:"Xem thời gian hoạt động"
                }]')
        fi

        if has_permission "$CHAT_ID" "resources"; then
            COMMANDS=$(echo "$COMMANDS" | jq \
                '. + [{
                    command:"resources",
                    description:"Xem CPU và RAM"
                }]')
        fi

        if has_permission "$CHAT_ID" "restarts"; then
            COMMANDS=$(echo "$COMMANDS" | jq \
                '. + [{
                    command:"restarts",
                    description:"Xem số lần container khởi động lại"
                }]')
        fi

        if has_permission "$CHAT_ID" "health"; then
            COMMANDS=$(echo "$COMMANDS" | jq \
                '. + [{
                    command:"health",
                    description:"Kiểm tra API Spring Boot"
                }]')
        fi

        if has_permission "$CHAT_ID" "history"; then
            COMMANDS=$(echo "$COMMANDS" | jq \
                '. + [{
                    command:"history",
                    description:"Xem lịch sử Docker image"
                }]')
        fi

        if [ "$CHAT_ID" = "$ADMIN_CHAT_ID" ]; then

            COMMANDS=$(echo "$COMMANDS" | jq '
            . + [
              {
                command:"add",
                description:"Duyệt người dùng đang chờ"
              },
              {
                command:"remove",
                description:"Xóa thành viên"
              },
              {
                command:"setrole",
                description:"Đổi vai trò thành viên"
              },
              {
                command:"allow",
                description:"Cấp thêm quyền"
              },
              {
                command:"deny",
                description:"Thu hồi quyền"
              },
              {
                command:"members",
                description:"Xem danh sách thành viên"
              },
              {
                command:"permissions",
                description:"Xem quyền thành viên"
              }
            ]')
        fi

    fi

    local PAYLOAD

    PAYLOAD=$(jq -nc \
        --argjson chat_id "$CHAT_ID" \
        --argjson commands "$COMMANDS" \
        '{
            scope:{
                type:"chat",
                chat_id:$chat_id
            },
            commands:$commands
        }')

    curl -sS \
        -X POST \
        "https://api.telegram.org/bot${TOKEN}/setMyCommands" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" > /dev/null
}




show_pending_users() {
    local CHAT_ID="$1"

    local ROWS=""
    local FIRST=true

    while IFS='|' read -r ID NAME; do

        [ -z "$ID" ] && continue
        [ -z "$NAME" ] && continue

        [ "$ID" = "$ADMIN_CHAT_ID" ] && continue

       
        if grep -q "^${ID}|" "$MEMBERS"; then
            continue
        fi

        ROW=$(jq -nc \
            --arg approve "pending:$ID" \
            --arg delete "deletepending:$ID" \
            --arg name "@$NAME" \
            '[
                {
                    text:$name,
                    callback_data:$approve
                },
                {
                    text:"Xóa",
                    callback_data:$delete
                }
            ]')

        if $FIRST; then
            ROWS="$ROW"
            FIRST=false
        else
            ROWS="$ROWS,$ROW"
        fi

    done < "$KNOWN_USERS"

    if [ -z "$ROWS" ]; then

        send_message "$CHAT_ID" \
"Hiện không có người dùng nào đang chờ duyệt."

        return
    fi

    KEYBOARD="{\"inline_keyboard\":[$ROWS]}"

    send_keyboard \
        "$CHAT_ID" \
        "Danh sách người dùng đang chờ duyệt:" \
        "$KEYBOARD"
}


show_member_users() {
    local CHAT_ID="$1"
    local ACTION="$2"
    local TEXT="$3"

    local ROWS=""
    local FIRST=true

    while IFS='|' read -r ID NAME ROLE; do

        [ -z "$ID" ] && continue
        [ -z "$NAME" ] && continue

        local ROLE_NAME="$ROLE"

        if [ "$ROLE" = "viewer" ]; then
            ROLE_NAME="Người xem"
        elif [ "$ROLE" = "operator" ]; then
            ROLE_NAME="Vận hành"
        fi

        BUTTON=$(jq -nc \
            --arg text "@$NAME - $ROLE_NAME" \
            --arg data "${ACTION}:$ID" \
            '{
                text:$text,
                callback_data:$data
            }')

        if $FIRST; then
            ROWS="[$BUTTON]"
            FIRST=false
        else
            ROWS="$ROWS,[$BUTTON]"
        fi

    done < "$MEMBERS"

    if [ -z "$ROWS" ]; then

        send_message "$CHAT_ID" \
"Hiện chưa có thành viên."

        return
    fi

    KEYBOARD="{\"inline_keyboard\":[$ROWS]}"

    send_keyboard \
        "$CHAT_ID" \
        "$TEXT" \
        "$KEYBOARD"
}


show_role_keyboard() {
    local CHAT_ID="$1"
    local TARGET_ID="$2"
    local ACTION="$3"

    local USERNAME
    USERNAME=$(get_username "$TARGET_ID")

    KEYBOARD=$(jq -nc \
        --arg viewer "${ACTION}:$TARGET_ID:viewer" \
        --arg operator "${ACTION}:$TARGET_ID:operator" \
        '{
            inline_keyboard:[
                [
                    {
                        text:"Người xem",
                        callback_data:$viewer
                    },
                    {
                        text:"Vận hành",
                        callback_data:$operator
                    }
                ],
                [
                    {
                        text:"Hủy",
                        callback_data:"cancel"
                    }
                ]
            ]
        }')

    send_keyboard \
        "$CHAT_ID" \
        "Chọn vai trò cho @$USERNAME:" \
        "$KEYBOARD"
}


show_permission_keyboard() {
    local CHAT_ID="$1"
    local TARGET_ID="$2"
    local ACTION="$3"

    local USERNAME
    USERNAME=$(get_username "$TARGET_ID")

    KEYBOARD=$(jq -nc \
        --arg a "${ACTION}:$TARGET_ID:status" \
        --arg b "${ACTION}:$TARGET_ID:version" \
        --arg c "${ACTION}:$TARGET_ID:logs" \
        --arg d "${ACTION}:$TARGET_ID:uptime" \
        --arg e "${ACTION}:$TARGET_ID:resources" \
        --arg f "${ACTION}:$TARGET_ID:restarts" \
        --arg g "${ACTION}:$TARGET_ID:health" \
        --arg h "${ACTION}:$TARGET_ID:history" \
        '{
            inline_keyboard:[
                [
                    {
                        text:"Trạng thái",
                        callback_data:$a
                    },
                    {
                        text:"Phiên bản",
                        callback_data:$b
                    }
                ],
                [
                    {
                        text:"Nhật ký",
                        callback_data:$c
                    },
                    {
                        text:"Thời gian hoạt động",
                        callback_data:$d
                    }
                ],
                [
                    {
                        text:"CPU / RAM",
                        callback_data:$e
                    },
                    {
                        text:"Số lần khởi động lại",
                        callback_data:$f
                    }
                ],
                [
                    {
                        text:"Kiểm tra API",
                        callback_data:$g
                    },
                    {
                        text:"Lịch sử image",
                        callback_data:$h
                    }
                ],
                [
                    {
                        text:"Hủy",
                        callback_data:"cancel"
                    }
                ]
            ]
        }')

    send_keyboard \
        "$CHAT_ID" \
        "Chọn quyền của @$USERNAME:" \
        "$KEYBOARD"
}



process_callback() {
    local CALLBACK_ID="$1"
    local CHAT_ID="$2"
    local DATA="$3"

    answer_callback "$CALLBACK_ID"


    if [ "$CHAT_ID" != "$ADMIN_CHAT_ID" ]; then

        send_message "$CHAT_ID" \
"Bạn không có quyền thực hiện thao tác này."

        return
    fi

    local ACTION
    local TARGET_ID
    local VALUE
    local USERNAME

    IFS=':' read -r ACTION TARGET_ID VALUE <<< "$DATA"

    USERNAME=$(get_username "$TARGET_ID")


    case "$ACTION" in



        pending)

            if [ -z "$USERNAME" ]; then
                send_message "$CHAT_ID" "Không tìm thấy người dùng."
                return
            fi

            show_role_keyboard \
                "$CHAT_ID" \
                "$TARGET_ID" \
                "addrole"
            ;;


   

        deletepending)

            if [ -z "$USERNAME" ]; then
                send_message "$CHAT_ID" "Không tìm thấy người dùng."
                return
            fi

            KEYBOARD=$(jq -nc \
                --arg yes "deletependingconfirm:$TARGET_ID:yes" \
                '{
                    inline_keyboard:[
                        [
                            {
                                text:"Xác nhận xóa",
                                callback_data:$yes
                            },
                            {
                                text:"Hủy",
                                callback_data:"cancel"
                            }
                        ]
                    ]
                }')

            send_keyboard \
                "$CHAT_ID" \
                "Xóa @$USERNAME khỏi danh sách chờ?" \
                "$KEYBOARD"
            ;;


        deletependingconfirm)

            if [ -z "$USERNAME" ]; then
                send_message "$CHAT_ID" "Không tìm thấy người dùng."
                return
            fi

            sed -i "/^${TARGET_ID}|/d" "$KNOWN_USERS"
            sed -i "/^${TARGET_ID}|/d" "$PERMISSIONS"

            update_command_menu "$TARGET_ID"

            send_message "$CHAT_ID" \
"Đã xóa @$USERNAME khỏi danh sách chờ."

            send_message "$TARGET_ID" \
"Yêu cầu đăng ký của bạn đã được xóa.

Bạn có thể dùng /start để đăng ký lại."
            ;;




        addrole)

            if [ "$VALUE" != "viewer" ] &&
               [ "$VALUE" != "operator" ]; then

                send_message "$CHAT_ID" "Vai trò không hợp lệ."
                return
            fi

            if [ -z "$USERNAME" ]; then
                send_message "$CHAT_ID" "Không tìm thấy người dùng."
                return
            fi

            sed -i "/^${TARGET_ID}|/d" "$MEMBERS"

            echo "${TARGET_ID}|${USERNAME}|${VALUE}" \
                >> "$MEMBERS"

            update_command_menu "$TARGET_ID"

            if [ "$VALUE" = "viewer" ]; then
                ROLE_NAME="Người xem"
            else
                ROLE_NAME="Vận hành"
            fi

            send_message "$CHAT_ID" \
"Đã thêm thành viên.

Người dùng: @$USERNAME
Vai trò: $ROLE_NAME"

            send_message "$TARGET_ID" \
"Tài khoản của bạn đã được cấp quyền.

Vai trò: $ROLE_NAME

Dùng /help để xem các lệnh được phép sử dụng."
            ;;




        removeuser)

            if [ -z "$USERNAME" ]; then
                send_message "$CHAT_ID" "Không tìm thấy người dùng."
                return
            fi

            KEYBOARD=$(jq -nc \
                --arg yes "removeconfirm:$TARGET_ID:yes" \
                '{
                    inline_keyboard:[
                        [
                            {
                                text:"Xác nhận xóa",
                                callback_data:$yes
                            },
                            {
                                text:"Hủy",
                                callback_data:"cancel"
                            }
                        ]
                    ]
                }')

            send_keyboard \
                "$CHAT_ID" \
                "Xóa @$USERNAME khỏi danh sách thành viên?" \
                "$KEYBOARD"
            ;;


        removeconfirm)

            if [ -z "$USERNAME" ]; then
                send_message "$CHAT_ID" "Không tìm thấy người dùng."
                return
            fi

            sed -i "/^${TARGET_ID}|/d" "$MEMBERS"
            sed -i "/^${TARGET_ID}|/d" "$PERMISSIONS"

            update_command_menu "$TARGET_ID"

            send_message "$CHAT_ID" \
"Đã xóa @$USERNAME khỏi danh sách thành viên."

            send_message "$TARGET_ID" \
"Quyền truy cập bot của bạn đã bị thu hồi.

Bạn có thể dùng /start để gửi lại yêu cầu đăng ký."
            ;;



        setroleuser)

            if [ -z "$USERNAME" ]; then
                send_message "$CHAT_ID" "Không tìm thấy người dùng."
                return
            fi

            show_role_keyboard \
                "$CHAT_ID" \
                "$TARGET_ID" \
                "setrolevalue"
            ;;


        setrolevalue)

            if [ "$VALUE" != "viewer" ] &&
               [ "$VALUE" != "operator" ]; then

                send_message "$CHAT_ID" "Vai trò không hợp lệ."
                return
            fi

            if ! grep -q "^${TARGET_ID}|" "$MEMBERS"; then

                send_message "$CHAT_ID" \
"Người dùng này không phải thành viên."

                return
            fi

            sed -i "/^${TARGET_ID}|/d" "$MEMBERS"

            echo "${TARGET_ID}|${USERNAME}|${VALUE}" \
                >> "$MEMBERS"

            update_command_menu "$TARGET_ID"

            if [ "$VALUE" = "viewer" ]; then
                ROLE_NAME="Người xem"
            else
                ROLE_NAME="Vận hành"
            fi

            send_message "$CHAT_ID" \
"Đã thay đổi vai trò.

Người dùng: @$USERNAME
Vai trò mới: $ROLE_NAME"

            send_message "$TARGET_ID" \
"Vai trò của bạn đã được thay đổi.

Vai trò mới: $ROLE_NAME"
            ;;



        allowuser)

            show_permission_keyboard \
                "$CHAT_ID" \
                "$TARGET_ID" \
                "allowperm"
            ;;


        allowperm)

            case "$VALUE" in
                status|version|logs|uptime|resources|restarts|health|history)
                    ;;
                *)
                    send_message "$CHAT_ID" "Quyền không hợp lệ."
                    return
                    ;;
            esac

            if ! grep -q "^${TARGET_ID}|" "$MEMBERS"; then

                send_message "$CHAT_ID" \
"Người dùng này không phải thành viên."

                return
            fi

            sed -i \
                "/^${TARGET_ID}|${VALUE}|/d" \
                "$PERMISSIONS"

            echo "${TARGET_ID}|${VALUE}|allow" \
                >> "$PERMISSIONS"

            update_command_menu "$TARGET_ID"

            send_message "$CHAT_ID" \
"Đã cấp quyền.

Người dùng: @$USERNAME
Lệnh: /$VALUE"
            ;;


  

        denyuser)

            show_permission_keyboard \
                "$CHAT_ID" \
                "$TARGET_ID" \
                "denyperm"
            ;;


        denyperm)

            case "$VALUE" in
                status|version|logs|uptime|resources|restarts|health|history)
                    ;;
                *)
                    send_message "$CHAT_ID" "Quyền không hợp lệ."
                    return
                    ;;
            esac

            if ! grep -q "^${TARGET_ID}|" "$MEMBERS"; then

                send_message "$CHAT_ID" \
"Người dùng này không phải thành viên."

                return
            fi

            sed -i \
                "/^${TARGET_ID}|${VALUE}|/d" \
                "$PERMISSIONS"

            echo "${TARGET_ID}|${VALUE}|deny" \
                >> "$PERMISSIONS"

            update_command_menu "$TARGET_ID"

            send_message "$CHAT_ID" \
"Đã thu hồi quyền.

Người dùng: @$USERNAME
Lệnh: /$VALUE"
            ;;


     

        permissionsuser)

            if [ -z "$USERNAME" ]; then
                send_message "$CHAT_ID" "Không tìm thấy người dùng."
                return
            fi

            local ROLE
            local ROLE_NAME
            local RESULT

            ROLE=$(get_role "$TARGET_ID")

            if [ "$ROLE" = "viewer" ]; then
                ROLE_NAME="Người xem"
            elif [ "$ROLE" = "operator" ]; then
                ROLE_NAME="Vận hành"
            else
                ROLE_NAME="$ROLE"
            fi

            RESULT="QUYỀN THÀNH VIÊN

Người dùng: @$USERNAME
Vai trò: $ROLE_NAME

Các lệnh được phép:"

            for P in \
                status \
                version \
                logs \
                uptime \
                resources \
                restarts \
                health \
                history
            do

                if has_permission "$TARGET_ID" "$P"; then
                    RESULT="$RESULT
/$P: Có quyền"
                else
                    RESULT="$RESULT
/$P: Không có quyền"
                fi

            done

            send_message "$CHAT_ID" "$RESULT"
            ;;


  

        cancel)

            send_message "$CHAT_ID" "Đã hủy thao tác."
            ;;


        *)

            send_message "$CHAT_ID" "Thao tác không hợp lệ."
            ;;

    esac
}



while true; do

    RESPONSE=$(curl -s \
        "https://api.telegram.org/bot${TOKEN}/getUpdates?offset=${OFFSET}&timeout=30")

    UPDATE_IDS=$(echo "$RESPONSE" |
        jq -r '.result[].update_id')

    for UPDATE_ID in $UPDATE_IDS; do

        UPDATE=$(echo "$RESPONSE" |
            jq -c ".result[] | select(.update_id == $UPDATE_ID)")

        OFFSET=$((UPDATE_ID + 1))



        CALLBACK_ID=$(echo "$UPDATE" |
            jq -r '.callback_query.id // empty')

        if [ -n "$CALLBACK_ID" ]; then

            CALLBACK_CHAT_ID=$(echo "$UPDATE" |
                jq -r '.callback_query.message.chat.id // empty')

            CALLBACK_DATA=$(echo "$UPDATE" |
                jq -r '.callback_query.data // empty')

            process_callback \
                "$CALLBACK_ID" \
                "$CALLBACK_CHAT_ID" \
                "$CALLBACK_DATA"

            continue
        fi




        CHAT_ID=$(echo "$UPDATE" |
            jq -r '.message.chat.id // empty')

        COMMAND=$(echo "$UPDATE" |
            jq -r '.message.text // empty')

        USERNAME=$(echo "$UPDATE" |
            jq -r '.message.from.username // empty')

        [ -z "$CHAT_ID" ] && continue
        [ -z "$COMMAND" ] && continue



        if [ "$COMMAND" = "/start" ]; then

            if [ -z "$USERNAME" ]; then

                send_message "$CHAT_ID" \
"Tài khoản Telegram của bạn cần có username trước khi đăng ký."

                continue
            fi

           
            sed -i "/^${CHAT_ID}|/d" "$KNOWN_USERS"

            echo "${CHAT_ID}|${USERNAME}" \
                >> "$KNOWN_USERS"

            update_command_menu "$CHAT_ID"

            if [ "$CHAT_ID" = "$ADMIN_CHAT_ID" ]; then

                send_message "$CHAT_ID" \
"Bot quản lý CI/CD đã sẵn sàng.

Vai trò: Quản trị viên

Dùng /help để xem danh sách lệnh."

            elif is_member "$CHAT_ID"; then

                ROLE=$(get_role "$CHAT_ID")

                if [ "$ROLE" = "viewer" ]; then
                    ROLE_NAME="Người xem"
                else
                    ROLE_NAME="Vận hành"
                fi

                send_message "$CHAT_ID" \
"Tài khoản của bạn đã được đăng ký.

Vai trò: $ROLE_NAME

Dùng /help để xem các lệnh được phép."

            else

                send_message "$CHAT_ID" \
"Đã gửi yêu cầu đăng ký.

Tài khoản: @$USERNAME
Trạng thái: Đang chờ quản trị viên duyệt."

            fi

            continue
        fi




        if ! is_member "$CHAT_ID"; then

            send_message "$CHAT_ID" \
"Tài khoản của bạn chưa được cấp quyền.

Vui lòng chờ quản trị viên duyệt."

            continue
        fi


        CMD=$(echo "$COMMAND" | awk '{print $1}')
        CMD="${CMD#/}"



        case "$CMD" in

            add)

                if [ "$CHAT_ID" != "$ADMIN_CHAT_ID" ]; then
                    send_message "$CHAT_ID" "Bạn không có quyền sử dụng lệnh này."
                    continue
                fi

                show_pending_users "$CHAT_ID"

                continue
                ;;


            remove)

                if [ "$CHAT_ID" != "$ADMIN_CHAT_ID" ]; then
                    send_message "$CHAT_ID" "Bạn không có quyền sử dụng lệnh này."
                    continue
                fi

                show_member_users \
                    "$CHAT_ID" \
                    "removeuser" \
                    "Chọn thành viên cần xóa:"

                continue
                ;;


            setrole)

                if [ "$CHAT_ID" != "$ADMIN_CHAT_ID" ]; then
                    send_message "$CHAT_ID" "Bạn không có quyền sử dụng lệnh này."
                    continue
                fi

                show_member_users \
                    "$CHAT_ID" \
                    "setroleuser" \
                    "Chọn thành viên cần đổi vai trò:"

                continue
                ;;


            allow)

                if [ "$CHAT_ID" != "$ADMIN_CHAT_ID" ]; then
                    send_message "$CHAT_ID" "Bạn không có quyền sử dụng lệnh này."
                    continue
                fi

                show_member_users \
                    "$CHAT_ID" \
                    "allowuser" \
                    "Chọn thành viên cần cấp quyền:"

                continue
                ;;


            deny)

                if [ "$CHAT_ID" != "$ADMIN_CHAT_ID" ]; then
                    send_message "$CHAT_ID" "Bạn không có quyền sử dụng lệnh này."
                    continue
                fi

                show_member_users \
                    "$CHAT_ID" \
                    "denyuser" \
                    "Chọn thành viên cần thu hồi quyền:"

                continue
                ;;


            members)

                if [ "$CHAT_ID" != "$ADMIN_CHAT_ID" ]; then
                    send_message "$CHAT_ID" "Bạn không có quyền sử dụng lệnh này."
                    continue
                fi

                RESULT="DANH SÁCH THÀNH VIÊN"

                if [ ! -s "$MEMBERS" ]; then

                    RESULT="$RESULT

Chưa có thành viên."

                else

                    while IFS='|' read -r ID NAME ROLE; do

                        [ -z "$ID" ] && continue

                        if [ "$ROLE" = "viewer" ]; then
                            ROLE_NAME="Người xem"
                        else
                            ROLE_NAME="Vận hành"
                        fi

                        RESULT="$RESULT

@$NAME
Vai trò: $ROLE_NAME"

                    done < "$MEMBERS"

                fi

                send_message "$CHAT_ID" "$RESULT"

                continue
                ;;


            permissions)

                if [ "$CHAT_ID" != "$ADMIN_CHAT_ID" ]; then
                    send_message "$CHAT_ID" "Bạn không có quyền sử dụng lệnh này."
                    continue
                fi

                show_member_users \
                    "$CHAT_ID" \
                    "permissionsuser" \
                    "Chọn thành viên cần xem quyền:"

                continue
                ;;

        esac



        if [ "$CMD" = "help" ]; then

            ROLE=$(get_role "$CHAT_ID")

            if [ "$ROLE" = "admin" ]; then
                ROLE_NAME="Quản trị viên"
            elif [ "$ROLE" = "operator" ]; then
                ROLE_NAME="Vận hành"
            else
                ROLE_NAME="Người xem"
            fi

            RESULT="BOT GIÁM SÁT CI/CD

Vai trò: $ROLE_NAME

Các lệnh bạn có thể sử dụng:"

            for P in \
                status \
                version \
                logs \
                uptime \
                resources \
                restarts \
                health \
                history
            do

                if has_permission "$CHAT_ID" "$P"; then
                    RESULT="$RESULT
/$P"
                fi

            done

            if [ "$CHAT_ID" = "$ADMIN_CHAT_ID" ]; then

                RESULT="$RESULT

Quản lý thành viên:
/add - Duyệt người dùng
/remove - Xóa thành viên
/setrole - Đổi vai trò
/allow - Cấp quyền
/deny - Thu hồi quyền
/members - Danh sách thành viên
/permissions - Xem quyền"

            fi

            send_message "$CHAT_ID" "$RESULT"

            continue
        fi


      

        case "$CMD" in

            status|version|logs|uptime|resources|restarts|health|history)

                if ! has_permission "$CHAT_ID" "$CMD"; then

                    send_message "$CHAT_ID" \
"Bạn không có quyền sử dụng /$CMD."

                    continue
                fi
                ;;


            *)

                send_message "$CHAT_ID" \
"Lệnh không hợp lệ.

Dùng /help để xem các lệnh bạn có thể sử dụng."

                continue
                ;;

        esac


       

        case "$CMD" in

            status)

                STATE=$(docker inspect cicd-app \
                    --format='{{.State.Status}}' \
                    2>/dev/null)

                HEALTH=$(docker inspect cicd-app \
                    --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' \
                    2>/dev/null)

                case "$STATE" in
                    running)
                        STATE_VI="Đang chạy"
                        ;;
                    exited)
                        STATE_VI="Đã dừng"
                        ;;
                    restarting)
                        STATE_VI="Đang khởi động lại"
                        ;;
                    paused)
                        STATE_VI="Đang tạm dừng"
                        ;;
                    *)
                        STATE_VI="$STATE"
                        ;;
                esac

                case "$HEALTH" in
                    healthy)
                        HEALTH_VI="Bình thường"
                        ;;
                    unhealthy)
                        HEALTH_VI="Có lỗi"
                        ;;
                    starting)
                        HEALTH_VI="Đang kiểm tra"
                        ;;
                    N/A)
                        HEALTH_VI="Không có Health Check"
                        ;;
                    *)
                        HEALTH_VI="$HEALTH"
                        ;;
                esac

                RESULT="TRẠNG THÁI HỆ THỐNG

Container: cicd-app
Trạng thái: $STATE_VI
Health Check: $HEALTH_VI"
                ;;


            version)

                IMAGE=$(docker inspect cicd-app \
                    --format='{{.Config.Image}}' \
                    2>/dev/null)

                RESULT="PHIÊN BẢN ĐANG CHẠY

Docker image:
$IMAGE"
                ;;


            logs)

                LOG_DATA=$(docker logs \
                    --tail 20 \
                    cicd-app 2>&1)

                LOG_DATA=$(echo "$LOG_DATA" |
                    tail -c 3500)

                RESULT="NHẬT KÝ ỨNG DỤNG

20 dòng gần nhất:

$LOG_DATA"
                ;;


            uptime)

                STARTED=$(docker inspect cicd-app \
                    --format='{{.State.StartedAt}}' \
                    2>/dev/null)

                if [ -n "$STARTED" ]; then

                    START_SECONDS=$(date -d "$STARTED" +%s)
                    NOW_SECONDS=$(date +%s)

                    TOTAL=$((NOW_SECONDS - START_SECONDS))

                    DAYS=$((TOTAL / 86400))
                    HOURS=$(((TOTAL % 86400) / 3600))
                    MINUTES=$(((TOTAL % 3600) / 60))

                    RESULT="THỜI GIAN HOẠT ĐỘNG

Container: cicd-app
Thời gian: ${DAYS} ngày ${HOURS} giờ ${MINUTES} phút"

                else

                    RESULT="Không thể đọc thời gian hoạt động của container."

                fi
                ;;


            resources)

                STATS=$(docker stats \
                    cicd-app \
                    --no-stream \
                    --format '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}' \
                    2>/dev/null)

                CPU=$(echo "$STATS" | cut -d'|' -f1)
                MEMORY=$(echo "$STATS" | cut -d'|' -f2)
                MEMORY_PERCENT=$(echo "$STATS" | cut -d'|' -f3)

                RESULT="TÀI NGUYÊN HỆ THỐNG

Container: cicd-app
CPU: $CPU
RAM: $MEMORY
Sử dụng RAM: $MEMORY_PERCENT"
                ;;


            restarts)

                COUNT=$(docker inspect cicd-app \
                    --format='{{.RestartCount}}' \
                    2>/dev/null)

                RESULT="LỊCH SỬ KHỞI ĐỘNG LẠI

Container: cicd-app
Số lần khởi động lại: $COUNT"
                ;;


            health)

                HTTP_CODE=$(curl -s \
                    -o /tmp/cicd_health_body.txt \
                    -w '%{http_code}' \
                    http://localhost:8080/ci-cd)

                BODY=$(cat /tmp/cicd_health_body.txt)

                if [ "$HTTP_CODE" = "200" ]; then
                    STATUS_TEXT="API hoạt động bình thường"
                else
                    STATUS_TEXT="API đang có vấn đề"
                fi

                RESULT="KIỂM TRA API

Trạng thái: $STATUS_TEXT
HTTP Status: $HTTP_CODE

Phản hồi:
$BODY"
                ;;


            history)

                IMAGES=$(docker images \
                    quocdat233/cicd-spring \
                    --format '{{.Repository}}:{{.Tag}} | {{.CreatedSince}}' |
                    head -10)

                if [ -z "$IMAGES" ]; then
                    IMAGES="Không tìm thấy Docker image."
                fi

                RESULT="LỊCH SỬ DOCKER IMAGE

10 image gần nhất:

$IMAGES"
                ;;

        esac


        send_message "$CHAT_ID" "$RESULT"

    done

done