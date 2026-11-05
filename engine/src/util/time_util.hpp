/******************************************************************************
Copyright (C) 2023 by xurei <xureilab@gmail.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
******************************************************************************/

#ifndef SHADERTASTIC_TIME_UTIL_HPP
#define SHADERTASTIC_TIME_UTIL_HPP

#include <chrono>

inline unsigned long get_time_ms() {
    const auto now = std::chrono::system_clock::now();
    const auto now_ms = std::chrono::time_point_cast<std::chrono::milliseconds>(now);
    const auto value = now_ms.time_since_epoch();
    const unsigned long duration = static_cast<unsigned long>(value.count());

    return duration;
}

inline unsigned long get_time_us() {
    const auto now = std::chrono::system_clock::now();
    const auto now_us = std::chrono::time_point_cast<std::chrono::microseconds>(now);
    const auto value = now_us.time_since_epoch();
    const unsigned long duration = static_cast<unsigned long>(value.count());

    return duration;
}

#endif // SHADERTASTIC_TIME_UTIL_HPP
