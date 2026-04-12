cmake_minimum_required(VERSION 3.20)

project(RemoteJoyLite-cross)

find_package(SDL3 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBUSB REQUIRED libusb-1.0)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -std=gnu11")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")

add_executable(${PROJECT_NAME}
  src/main.c
)

target_include_directories(${PROJECT_NAME} PRIVATE ${LIBUSB_INCLUDE_DIRS})
target_link_directories(${PROJECT_NAME} PRIVATE ${LIBUSB_LIBRARY_DIRS})
target_link_libraries(${PROJECT_NAME} SDL3::SDL3 ${LIBUSB_LIBRARIES})
target_include_directories(${PROJECT_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/..")
