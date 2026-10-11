cmake_minimum_required(VERSION 3.13)

# Output file is intercept_aar.dll / intercept_aar_x64.dll (or .so on Linux).
project(intercept_aar CXX)

option(USE_ENGINE_TYPES "Use the engine string type instead of std::string" OFF)
option(USE_64BIT_BUILD "USE_64BIT_BUILD" OFF)

if("${CMAKE_SIZEOF_VOID_P}" STREQUAL "8")
    set(USE_64BIT_BUILD ON)
endif()

if(USE_64BIT_BUILD)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PROJECT_SOURCE_DIR}/build/win64/")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${PROJECT_SOURCE_DIR}/build/linux64/")
else()
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${PROJECT_SOURCE_DIR}/build/win32/")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${PROJECT_SOURCE_DIR}/build/linux32/")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_INCLUDE_CURRENT_DIR ON)
set_property(GLOBAL PROPERTY USE_FOLDERS ON)
set(CMAKE_CONFIGURATION_TYPES "Debug;Release" CACHE STRING "" FORCE)

add_subdirectory(src)
