
#ifndef SLATE_H
#define SLATE_H

#ifndef MODULE 
#   error "define a module"
#endif

#include<stdint.h>
#include<stdlib.h>
#include<stdio.h>
#include<stdbool.h>
#include<stdarg.h>


typedef struct{
    char *data;
    size_t len;
}string_t;

typedef struct{
    string_t* arr;
    size_t len;
}string_array_t;

#define string_array_of(arr) ((string_array_t){.data=(arr), .len=sizeof(arr)/sizeof(*(arr))})
#define string_of(str) ((string_t){.data=(str), .len=strlen(str)})


typedef enum{
    CRITICAL, ERROR, WARNING, INFO, VERBOSE, DEBUG
}log_category_t;


typedef struct{
    uint16_t major; 
    uint16_t minor; 
    uint16_t patch; 
}version_t;


typedef struct{
    string_t key;
    struct{
        enum{
            INTEGER, REAL, STRING, BOOLEAN
        }type;
        union{
            int64_t  integer;
            double   real;
            string_t string;
            bool     boolean;
        }value;
    };
}config_t;

typedef void* module_interface_t;

typedef struct core_interface_t core_interface_t;

typedef void(*task_proc_t)(struct core_interface_t*);

typedef struct core_interface_t{
    uint64_t size;
    version_t version;
    //CONFIG
    void      (*config_set)         (config_t cfg);
    config_t  (*config_get)         (string_t key);
    int64_t   (*config_get_int)     (string_t key, int64_t default_);
    double    (*config_get_float)   (string_t key, double default_);
    string_t  (*config_get_string)  (string_t key, string_t default_);
    bool      (*config_get_bool)    (string_t key, bool default_);
    //LOGGING   
    void *__odin_console_log; //Odin console_log, do not use in C
    union{
        void (*__console_log)(log_category_t category, char *text); 
        void (*console_log)(log_category_t category, char *format, ...);
    };
    //MODULES
    void                (*module_set_interface)(string_t name, module_interface_t interface);
    module_interface_t *(*module_get_interface)(string_t name);
    version_t           (*module_get_version)  (string_t name);
    void                (*module_reload)       (string_t name);
    //TASKS
    void (*task_add_pool)    (string_t name, uint32_t threads);
    void (*task_add_repeated)(string_t name, string_t pool, task_proc_t task, string_array_t dependencies);
    void (*task_add_once)    (string_t name, string_t pool, task_proc_t task, string_array_t dependencies);
}core_interface_t;


char *_temp_sprintf(const char *format, ...){
    static char buf[256];
    va_list args;
    va_start(args, format);
    vsprintf(buf, format, args);
    va_end(args);
    return buf;
}

#define console_log(category, format, ...) __console_log(category, _temp_sprintf("[\033[34m%s | %s:\033[35m%d \033[93m%s()\033[0m] "format, MODULE, __FILE__, __LINE__, __func__ __VA_OPT__(,) __VA_ARGS__))

#endif
