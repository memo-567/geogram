if(CONFIG_IDF_TARGET_ESP32)
    idf_component_register(
        SRCS "sx1276.c"
        INCLUDE_DIRS "."
        REQUIRES driver log
        PRIV_REQUIRES freertos
    )
else()
    idf_component_register()
endif()
