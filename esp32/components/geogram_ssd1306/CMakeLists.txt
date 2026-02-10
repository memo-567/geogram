if(CONFIG_IDF_TARGET_ESP32S3)
    idf_component_register(
        SRCS "ssd1306.c"
        INCLUDE_DIRS "."
        REQUIRES driver log geogram_i2c
        PRIV_REQUIRES freertos
    )
else()
    idf_component_register()
endif()
