cmake_minimum_required(VERSION 3.20)

project(beamng_racecoach_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(beamng_racecoach_native
  main.cpp
)

if(MSVC)
  target_compile_options(beamng_racecoach_native PRIVATE /W4)
else()
  target_compile_options(beamng_racecoach_native PRIVATE -Wall -Wextra -Wpedantic)
endif()
