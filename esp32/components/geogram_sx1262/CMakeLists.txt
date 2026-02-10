if(CONFIG_IDF_TARGET_ESP32S3)
    idf_component_register(
        SRCS "sx1262.c"
        INCLUDE_DIRS "."
        REQUIRES driver log
        PRIV_REQUIRES freertos
    )
else()
    idf_component_register()
endif()
