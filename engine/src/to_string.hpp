#ifndef SHADERTASTIC_TO_STRING_HPP
#define SHADERTASTIC_TO_STRING_HPP

#include <sstream>
#include <string>

template <typename T> std::string to_string(T v) {
    std::ostringstream oss;
    oss << v;
    return oss.str();
}

#endif // SHADERTASTIC_TO_STRING_HPP
