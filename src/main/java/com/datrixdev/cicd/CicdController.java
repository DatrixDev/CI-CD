package com.datrixdev.cicd;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
@RestController
public class CicdController {

//    @GetMapping("/ci-cd")
//    public Map<String, Object> cicd() {
//        return Map.of(
//                "status",200,
//                "message", "Datcute"
//        );
//    }

    @Value("${app.message}")
    private String message;
    @GetMapping("/ci-cd")
    public Map<String, Object> cicd() {
        return Map.of(
                "status",200,
                "message", message
        );
    }

}
