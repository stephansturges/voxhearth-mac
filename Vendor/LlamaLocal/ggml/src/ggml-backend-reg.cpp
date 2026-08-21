#include "ggml-backend-impl.h"
#include "ggml-backend.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <vector>

#ifdef GGML_USE_METAL
#include "ggml-metal.h"
#endif

#ifdef GGML_USE_BLAS
#include "ggml-blas.h"
#endif

#ifdef GGML_USE_CPU
#include "ggml-cpu.h"
#endif

// VoxHearth intentionally supports a closed, statically linked backend set.
// Dynamic discovery, executable-directory searches, and environment-selected
// backend paths are not compiled into this runtime.
struct ggml_backend_registry {
    std::vector<ggml_backend_reg_t> backends;
    std::vector<ggml_backend_dev_t> devices;

    ggml_backend_registry() {
#ifdef GGML_USE_METAL
        register_backend(ggml_backend_metal_reg());
#endif
#ifdef GGML_USE_BLAS
        register_backend(ggml_backend_blas_reg());
#endif
#ifdef GGML_USE_CPU
        register_backend(ggml_backend_cpu_reg());
#endif
    }

    void register_backend(ggml_backend_reg_t reg) {
        if (reg == nullptr || std::find(backends.begin(), backends.end(), reg) != backends.end()) {
            return;
        }
        backends.push_back(reg);
        for (size_t index = 0; index < ggml_backend_reg_dev_count(reg); ++index) {
            register_device(ggml_backend_reg_dev_get(reg, index));
        }
    }

    void register_device(ggml_backend_dev_t device) {
        if (device != nullptr && std::find(devices.begin(), devices.end(), device) == devices.end()) {
            devices.push_back(device);
        }
    }
};

static ggml_backend_registry & get_reg() {
    static ggml_backend_registry registry;
    return registry;
}

void ggml_backend_register(ggml_backend_reg_t reg) {
    get_reg().register_backend(reg);
}

void ggml_backend_device_register(ggml_backend_dev_t device) {
    get_reg().register_device(device);
}

static bool striequals(const char * left, const char * right) {
    if (left == nullptr || right == nullptr) {
        return left == right;
    }
    for (; *left != '\0' && *right != '\0'; ++left, ++right) {
        if (std::tolower(static_cast<unsigned char>(*left)) !=
            std::tolower(static_cast<unsigned char>(*right))) {
            return false;
        }
    }
    return *left == *right;
}

size_t ggml_backend_reg_count() {
    return get_reg().backends.size();
}

ggml_backend_reg_t ggml_backend_reg_get(size_t index) {
    GGML_ASSERT(index < ggml_backend_reg_count());
    return get_reg().backends[index];
}

ggml_backend_reg_t ggml_backend_reg_by_name(const char * name) {
    for (size_t index = 0; index < ggml_backend_reg_count(); ++index) {
        ggml_backend_reg_t reg = ggml_backend_reg_get(index);
        if (striequals(ggml_backend_reg_name(reg), name)) {
            return reg;
        }
    }
    return nullptr;
}

size_t ggml_backend_dev_count() {
    return get_reg().devices.size();
}

ggml_backend_dev_t ggml_backend_dev_get(size_t index) {
    GGML_ASSERT(index < ggml_backend_dev_count());
    return get_reg().devices[index];
}

ggml_backend_dev_t ggml_backend_dev_by_name(const char * name) {
    for (size_t index = 0; index < ggml_backend_dev_count(); ++index) {
        ggml_backend_dev_t device = ggml_backend_dev_get(index);
        if (striequals(ggml_backend_dev_name(device), name)) {
            return device;
        }
    }
    return nullptr;
}

ggml_backend_dev_t ggml_backend_dev_by_type(enum ggml_backend_dev_type type) {
    for (size_t index = 0; index < ggml_backend_dev_count(); ++index) {
        ggml_backend_dev_t device = ggml_backend_dev_get(index);
        if (ggml_backend_dev_type(device) == type) {
            return device;
        }
    }
    return nullptr;
}

ggml_backend_t ggml_backend_init_by_name(const char * name, const char * params) {
    ggml_backend_dev_t device = ggml_backend_dev_by_name(name);
    return device == nullptr ? nullptr : ggml_backend_dev_init(device, params);
}

ggml_backend_t ggml_backend_init_by_type(enum ggml_backend_dev_type type, const char * params) {
    ggml_backend_dev_t device = ggml_backend_dev_by_type(type);
    return device == nullptr ? nullptr : ggml_backend_dev_init(device, params);
}

ggml_backend_t ggml_backend_init_best() {
    ggml_backend_dev_t device = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_GPU);
    device = device != nullptr ? device : ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_IGPU);
    device = device != nullptr ? device : ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU);
    return device == nullptr ? nullptr : ggml_backend_dev_init(device, nullptr);
}

ggml_backend_reg_t ggml_backend_load(const char *) {
    return nullptr;
}

void ggml_backend_unload(ggml_backend_reg_t) {
    // Static process-lifetime backends are never unloaded dynamically.
}

void ggml_backend_load_all() {
    // Construction of the static registry is sufficient.
    (void) get_reg();
}

void ggml_backend_load_all_from_path(const char *) {
    // External backend paths are deliberately unsupported.
    (void) get_reg();
}
