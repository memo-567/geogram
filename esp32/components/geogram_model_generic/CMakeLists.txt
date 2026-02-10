# Only build for Generic ESP32
if("${IDF_TARGET}" STREQUAL "esp32")
    idf_component_register(
        SRCS "model_init.c"
        INCLUDE_DIRS "."
        REQUIRES driver log
    )
else()
    idf_component_register()
endif()
