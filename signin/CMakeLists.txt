cmake_minimum_required(VERSION 3.16)
project(edulauncher-signin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Widgets WebEngineWidgets)

add_executable(edulauncher-signin main.cpp)
target_link_libraries(edulauncher-signin Qt6::Core Qt6::Widgets Qt6::WebEngineWidgets)

install(TARGETS edulauncher-signin RUNTIME DESTINATION bin)
