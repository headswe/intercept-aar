file(GLOB_RECURSE AAR_SOURCES *.h *.hpp *.cpp)
source_group("src" FILES ${AAR_SOURCES})

# Intercept client headers and sources come from the git submodule.
set(INTERCEPT_CLIENT_PATH "${CMAKE_SOURCE_DIR}/intercept/src/client")
set(INTERCEPT_INCLUDE_PATH
    "${INTERCEPT_CLIENT_PATH}/headers"
    "${INTERCEPT_CLIENT_PATH}/headers/shared"
    "${INTERCEPT_CLIENT_PATH}/headers/client/"
    "${INTERCEPT_CLIENT_PATH}/headers/client/sqf")

if(USE_64BIT_BUILD)
    set(INTERCEPT_PLUGIN_NAME "${CMAKE_PROJECT_NAME}_x64")
else()
    set(INTERCEPT_PLUGIN_NAME "${CMAKE_PROJECT_NAME}")
endif()

file(GLOB INTERCEPT_HOST_SOURCES
    "${INTERCEPT_CLIENT_PATH}/intercept/client/*.cpp"
    "${INTERCEPT_CLIENT_PATH}/intercept/client/sqf/*.cpp"
    "${INTERCEPT_CLIENT_PATH}/intercept/shared/*.cpp")
source_group("intercept" FILES ${INTERCEPT_HOST_SOURCES})

add_library(${INTERCEPT_PLUGIN_NAME} SHARED ${AAR_SOURCES} ${INTERCEPT_HOST_SOURCES})
target_include_directories(${INTERCEPT_PLUGIN_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR} ${INTERCEPT_INCLUDE_PATH})

# All engine calls happen on the game thread; only file IO runs on our own thread.
target_compile_definitions(${INTERCEPT_PLUGIN_NAME} PRIVATE INTERCEPT_NO_THREAD_SAFETY)
if(USE_ENGINE_TYPES)
    target_compile_definitions(${INTERCEPT_PLUGIN_NAME} PRIVATE INTERCEPT_SQF_STRTYPE_RSTRING)
endif()

set_target_properties(${INTERCEPT_PLUGIN_NAME} PROPERTIES PREFIX "" FOLDER "${CMAKE_PROJECT_NAME}")

if(MSVC)
    set_property(TARGET ${INTERCEPT_PLUGIN_NAME} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(${INTERCEPT_PLUGIN_NAME} PRIVATE /MP /EHsc /bigobj)
else()
    target_compile_options(${INTERCEPT_PLUGIN_NAME} PRIVATE -fPIC -fpermissive -O2)
    target_link_options(${INTERCEPT_PLUGIN_NAME} PRIVATE -static-libgcc -static-libstdc++)
    find_package(Threads REQUIRED)
    target_link_libraries(${INTERCEPT_PLUGIN_NAME} PRIVATE Threads::Threads)
endif()
