package com.datrixdev.cicd;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
@RestController
public class CicdController {
    @GetMapping("/ci-cd")
    public Map<String, Object> cicd() {
        return Map.of(
                "status",200,
                "message","CI-CD Spring Boot"
        );
    }

}
