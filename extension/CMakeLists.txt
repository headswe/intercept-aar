cmake_minimum_required(VERSION 3.13)

# Output: arma_aar_x64.dll on Windows, arma_aar_x64.so on Linux.
project(arma_aar CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(AAR_TARGET arma_aar_x64)
else()
    set(AAR_TARGET arma_aar)
endif()

add_library(${AAR_TARGET} SHARED src/extension.cpp src/async_writer.cpp)
set_target_properties(${AAR_TARGET} PROPERTIES PREFIX "" CXX_VISIBILITY_PRESET hidden)
set_target_properties(${AAR_TARGET} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${PROJECT_SOURCE_DIR}/build/$<CONFIG>"
    LIBRARY_OUTPUT_DIRECTORY "${PROJECT_SOURCE_DIR}/build/$<CONFIG>")

if(MSVC)
    # Static CRT so the DLL needs no Visual C++ redistributable on the server.
    set_property(TARGET ${AAR_TARGET} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
    target_compile_options(${AAR_TARGET} PRIVATE /W4 /EHsc)
else()
    target_compile_options(${AAR_TARGET} PRIVATE -Wall -Wextra -O2)
    target_link_options(${AAR_TARGET} PRIVATE -static-libgcc -static-libstdc++)
    find_package(Threads REQUIRED)
    target_link_libraries(${AAR_TARGET} PRIVATE Threads::Threads)
endif()

option(AAR_TESTS "Build the converter tests" OFF)
if(AAR_TESTS)
    enable_testing()
    add_executable(aar_tests tests/test_sqf_json.cpp)
    target_include_directories(aar_tests PRIVATE src)
    add_test(NAME aar_tests COMMAND aar_tests)
endif()
