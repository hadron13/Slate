package slate

import "core:c"
import "core:c/libc"
import "core:dynlib"
import "core:fmt" 
import "core:log"
import "core:mem"
import "core:os"
import "core:container/topological_sort"
import "core:sync"
import "core:slice"
import "core:strings"
import "core:strconv"
import "core:sys/windows"
import "core:thread"
import "core:time"

import "base:runtime"

MODULE :: #config(MOD, "Core") 

log_category :: enum c.int {CRITICAL, ERROR, WARNING, INFO, VERBOSE, DEBUG}

version :: struct{
    major : u16,
    minor : u16,
    patch : u16
}

config :: struct{
    key: string,
    value : union{
        string, i64, f64, b8
    }
}

module_interface :: distinct rawptr

@private
module :: struct{
    name              : string,
    module_version    : version,
    interface         : module_interface,
    library           : dynlib.Library,
    dependencies      : []string,
}

@private
task_proc :: proc"c"(core: ^core_interface)

@private
task_status :: enum{
    WAITING, RUNNING, DONE
}

@private
task :: struct{
    name      : string,
    status    : task_status,
    repeatable: bool,
    allocator : mem.Allocator,
    procedure : task_proc, 
    dependencies : []string,
}

@private
task_pool :: struct{
    name        : string,
    mutex       : sync.Mutex,
    threads     : []^thread.Thread,
    is_running  : bool,
    is_sorted   : bool,

    tasks        : map[string]task,
    tasks_sorted : [dynamic]string,
    task_sorter  : topological_sort.Sorter(string),
    task_index   : int,
}

core_interface :: struct{
    size : u64,
    version : version,
    //CONFIG
    config_set          : proc"c"(cfg : config) ,
    config_get          : proc"c"(key : string) -> config,
    config_get_int      : proc"c"(key : string, default : i64 = 0) -> i64,
    config_get_float    : proc"c"(key : string, default : f64 = 0.0) -> f64,
    config_get_string   : proc"c"(key : string, default : string = "") -> string,
    config_get_bool     : proc"c"(key : string, default : b8 = false) -> b8,
    //LOGGING   
    log         : proc"c"(category: log_category, format: string, args: ..any, module := MODULE, location := #caller_location),
    c_log       : proc"c"(category: log_category, text: cstring),
    //MODULES
    module_set_interface: proc"c"(name: string, interface: module_interface),  
    module_set_version  : proc"c"(name: string, version : version),            
    module_get_interface: proc"c"(name: string) -> module_interface,      
    module_get_version  : proc"c"(name: string) -> version,             
    module_reload       : proc"c"(name: string), // hot-reloads module, optionally calling a reload() procedure   
    //TASKS
    task_add_pool       : proc"c"(name: string, threads: u32),
    task_add_repeated   : proc"c"(name: string, pool: string, task: task_proc,  dependencies: []string),
    task_add_once       : proc"c"(name: string, pool: string, task: task_proc,  dependencies: []string),
    //MISC 
    quit                : proc"c"(status: int) 
}


@private
configuration : map[string]config
@private
modules       : map[string]module
@private
task_pools    : map[string]task_pool

@private
log_level     : log_category
@private
interface     : core_interface


@private
main :: proc() {
    log_level = .DEBUG
    

    when ODIN_DEBUG{
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
    }

    when ODIN_OPTIMIZATION_MODE == .Speed || ODIN_OPTIMIZATION_MODE == .Aggressive{
        config_set({"log_level", "WARNING"})
    }

    interface = (core_interface){
        size_of(core_interface),
        {0, 0, 2},
        config_set,
        config_get,
        config_get_int,
        config_get_float,
        config_get_string,
        config_get_bool,
        console_log,
        c_console_log,
        interface_set,
        version_set,
        interface_get,
        version_get,
        nil,
        task_add_pool,
        task_add_repeated,
        task_add_once,
        quit,
    }

    console_log(.INFO, "starting")
    
    task_add_pool("main", u32(os.processor_core_count()/2))
    
    cwd := os.get_current_directory()
    
    console_log(.INFO, "loading configs")
    {
        config_file, ok := os.read_entire_file("config.txt")
        if ok{
            defer delete(config_file)
            iterator := string(config_file)

            for config in strings.split_lines_iterator(&iterator){
                config_parse(config)
            }
        }
        for arg in os.args{
            if arg[0] == '-' && strings.contains_rune(arg, '=') {
                console_log(.DEBUG, "%s", arg[1:])
                config_parse(arg[1:])
            }
        }
    }

    switch(config_get_string("log_level", "")){
        case "VERBOSE": log_level = .VERBOSE 
        case "INFO":    log_level = .INFO    
        case "WARNING": log_level = .WARNING 
        case "ERROR":   log_level = .ERROR   
        case "CRITICAL":log_level = .CRITICAL
        case: config_set({"log_level", "DEBUG"})
    }
    console_log(.INFO, "log level set to: %s", config_get_string("log_level"))

    console_log(.INFO, "loading mods...") 
    {
        mod_directory_path := config_get_string("mod_directory", "mods")
        mod_directory : os.Handle
        err : os.Error

        if mod_directory, err = os.open(mod_directory_path); err != nil{
            console_log(.ERROR, "could not open mods directory: %s", os.error_string(err))
            return 
        }
        defer os.close(mod_directory)


        mod_listings: []os.File_Info
        if mod_listings, err = os.read_dir(mod_directory, 512); err != nil{
            console_log(.ERROR, "could not list mods: %s", os.error_string(err))
            return 
        }
        defer delete(mod_listings)
        console_log(.INFO, "%i mods found", len(mod_listings))

        for listed_mod in mod_listings{
            mod_path := strings.concatenate([] string{cwd, "/", mod_directory_path, "/", listed_mod.name, "/", listed_mod.name, ".",dynlib.LIBRARY_FILE_EXTENSION})
            if(!os.exists(mod_path)){
                continue
            }
            //when ODIN_OS == .Windows{windows.SetDllDirectoryW()} //TODO add proper parameters
            
            injection_lib, ok := dynlib.load_library(mod_path) // TODO: code injection support 
        }

        for listed_mod in mod_listings{    
            console_log(.INFO, "loading module '%s'", listed_mod.name)

            mod_path := strings.concatenate([] string{cwd, "/", mod_directory_path, "/", listed_mod.name, "/", listed_mod.name, ".",dynlib.LIBRARY_FILE_EXTENSION})
            
            when ODIN_OS == .Windows{
                dll_directory := strings.concatenate([] string{cwd, "/", mod_directory_path, "/", listed_mod.name})
                windows.SetDllDirectoryW(windows.utf8_to_wstring(dll_directory))
                console_log(.INFO, "DLL directory: %s", dll_directory)
            }

            mod_lib, ok := dynlib.load_library(mod_path)
            if !ok{
                console_log(.ERROR, "Library loading error with mod at %s: %s", mod_path, dynlib.last_error())
                continue 
            }
            
            load_ptr, found := dynlib.symbol_address(mod_lib, "load")
            if !found{
                console_log(.ERROR, "Load procedure not found at %s", mod_path)
                continue
            }
        
            load_proc := cast(proc"c"(^core_interface)) load_ptr
            load_proc(&interface)
        }
    }
    task_runner_thread(&task_pools["main"])

    when ODIN_DEBUG{
        for _, leak in track.allocation_map {
            console_log(.DEBUG,"%v leaked %m\n", leak.location, leak.size)
        }
    }
}


@private
task_add_pool :: proc"c"(name: string, threads: u32){
    context = runtime.default_context()
    console_log(.INFO, "creating pool %s with %i threads", name, threads)

    task_pools[name] = {}
    pool := &task_pools[name]
    pool.name = name 
    pool.is_sorted = true
    pool.is_running= true 
    pool.task_index= 0

    sync.guard(&pool.mutex)
    pool.threads = make([]^thread.Thread, max(threads, 1))
    for _, i in pool.threads{
        pool.threads[i] = thread.create_and_start_with_data(pool, task_runner_thread)
	}
    topological_sort.init(&pool.task_sorter)
}
@private
task_add_internal :: proc"c"(name: string, pool: string, task: task_proc, repeat: bool,  dependencies: []string){
    context = runtime.default_context()
    
    if(task == nil){
        console_log(.ERROR, "Null procedure in task '%s', pool %s", name, pool)
        return
    }
    tpool := &task_pools[pool]
    
    sync.guard(&tpool.mutex) 
    tpool.tasks[name] = {name, .WAITING, repeat, context.allocator, task,  slice.clone(dependencies)}
    topological_sort.add_key(&tpool.task_sorter, name)
    tpool.is_sorted = false;

    if(dependencies != nil){
        for dependency in dependencies{
            // console_log(.DEBUG, "%p - %s", raw_data(dependency), dependency)
            if !(dependency in tpool.tasks){
                console_log(.WARNING, "task '%s' depends on unknown task '%s'", name, dependency)
            }
            topological_sort.add_dependency(&tpool.task_sorter, name, dependency)
        }
    }
}

@private
task_add_repeated :: proc"c"(name: string, pool: string, task: task_proc,  dependencies: []string){
    task_add_internal(name, pool, task, true, dependencies)
}
@private
task_add_once:: proc"c"(name: string, pool: string, task: task_proc,  dependencies: []string){
    task_add_internal(name, pool, task, false, dependencies)
}

@private
task_runner_thread :: proc(pool_ptr : rawptr){
    pool := cast(^task_pool)pool_ptr
    
    console_log(.INFO, "starting thread %i from pool %s", os.current_thread_id(), pool.name)
    for pool.is_running {
        task_execute(pool)
        // time.sleep(time.Second)
    }
}



@private
task_execute :: proc(pool: ^task_pool){ 
    sync.guard(&pool.mutex)

    if !pool.is_sorted{
        pool.is_sorted = true 
        pool.tasks_sorted, _ = topological_sort.sort(&pool.task_sorter)
    }
    if len(pool.tasks_sorted) == 0 do return
    
    task_to_run : ^task = nil

    no_tasks_left := true
    unbroken_done := true
       
    // console_log(.DEBUG, "pool %s, %i tasks", pool.name, len(pool.tasks))

    task_search:
    for name in pool.tasks_sorted[pool.task_index:]{
        // console_log(.DEBUG, "fetching task %s", name)
        // console_log(.DEBUG, "status %s", pool.tasks[name].status==.WAITING?"waiting":pool.tasks[name].status==.RUNNING?"running":"done")
        task := &pool.tasks[name]
        if task == nil{
            console_log(.ERROR, "task %s is null", name)
            continue 
        }
    
        if task.status == .DONE && unbroken_done{
            pool.task_index += 1
        }else do unbroken_done = false

        if task.status != .WAITING do continue task_search
        no_tasks_left = false

        for dep in task.dependencies{
            if pool.tasks[dep].status != .DONE do continue task_search
        } 
        task.status = .RUNNING
        task_to_run = task
        break
    }
    // console_log(.DEBUG, "------------")
    // console_log(.DEBUG, "index %i", pool.task_index)
    // for name in pool.tasks_sorted{
    //     console_log(.DEBUG, "%s \t- %s", name, pool.tasks[name].status==.WAITING?"waiting":pool.tasks[name].status==.RUNNING?"running":"done")
    // }
    
    if no_tasks_left{
        for name in pool.tasks_sorted{
            task := &pool.tasks[name]
            if !task.repeatable{
                relations := &pool.task_sorter.relations[name]
                for key, _ in relations.dependents{
                    delete_key(&relations.dependents, key)
                }
                delete_key(&pool.task_sorter.relations, name)
                pool.tasks_sorted, _ = topological_sort.sort(&pool.task_sorter)
                continue
            }
            if task.status == .DONE{
                task.status = .WAITING
            }
        }
        pool.task_index = 0
        return
    }
    if task_to_run == nil do return

    sync.unlock(&pool.mutex) 
    task_to_run.procedure(&interface)
    sync.lock(&pool.mutex)

    task_to_run.status = .DONE
}


@private
config_set :: proc"c"(cfg : config) {
    if str, is_string := cfg.value.(string); is_string{
        context = runtime.default_context()
        configuration[cfg.key] = {cfg.key, strings.clone(str)} 
        return
    }
    configuration[cfg.key] = cfg
}


@private
config_get          :: proc"c"(key : string) -> config{return configuration[key]}
@private
config_get_int      :: proc"c"(key : string, default : i64 = 0)     -> i64      {return (configuration[key] or_else (config){"", default}).value.(i64)     or_else default}
@private
config_get_float    :: proc"c"(key : string, default : f64 = 0.0)   -> f64      {return (configuration[key] or_else (config){"", default}).value.(f64)     or_else default}
@private
config_get_string   :: proc"c"(key : string, default : string = "") -> string   {return (configuration[key] or_else (config){"", default}).value.(string)  or_else default}
@private
config_get_bool     :: proc"c"(key : string, default : b8 = false)  -> b8       {return (configuration[key] or_else (config){"", default}).value.(b8)      or_else default}
     
    
@private
config_parse :: proc(text : string) {
    string_portions, _ := strings.split(text, "=")
    if len(string_portions) < 2{
        return
    }
    key := string_portions[0]
    value_string := string_portions[1]

    if strings.compare(value_string, "true") == 0{config_set({key, true})}
    if strings.compare(value_string, "false")== 0{config_set({key, false})}

    if floating, ok := strconv.parse_f64(value_string); ok{
        config_set({key, floating})
        return
    }

    if integer, ok := strconv.parse_i64(value_string); ok{
        config_set({key, integer})
        return
    }
    config_set({key, value_string})
} 

log_mutex : sync.Mutex
log_file  : os.Handle

@private
console_log :: proc"c"(category: log_category, format: string, args: ..any, module := MODULE, location := #caller_location) {
    if category > log_level{
        return
    }

    context = runtime.default_context()
    output_file := os.stderr
    prefix := ""
    hour, min, second := time.clock(time.now())
      
    switch category {
      case log_category.VERBOSE: prefix = "[\033[34mVERBSE\033[0m]["
      case log_category.INFO:    prefix = "[\033[34mINFO\033[0m]  ["
      case log_category.WARNING: prefix = "[\033[93mWARN\033[0m]  ["
      case log_category.ERROR:   prefix = "[\033[31mERROR\033[0m] ["
      case log_category.CRITICAL:prefix = "[\033[31mCRTCAL\033[0m]["
      case log_category.DEBUG:   prefix = "[\033[35mDEBUG\033[0m] ["
    }
    sync.guard(&log_mutex)
    backing : [256]byte
    header := strings.builder_from_bytes(backing[:])
   
    path_len := len(location.file_path)
    source_path := location.file_path[strings.last_index(location.file_path[0:path_len-20], "/"):]

    fmt.sbprint(&header, prefix)
    fmt.sbprintf(&header, "%02i:%02i:%02i] ", hour, min, second);
    fmt.sbprintf(&header, "[\033[34m%s | %s:\033[35m%d \033[93m%s()\033[0m] ", module, source_path , location.line, location.procedure)
    fmt.print(strings.to_string(header))
    
    msg_backing : [256]byte
    message := strings.builder_from_bytes(msg_backing[:])
    fmt.sbprintfln(&message, format, ..args)

    fmt.fprint(os.stderr, strings.to_string(message))
//    if os.is_file_handle(log_file){
//        fmt.fprint(log_file, strings.to_string(message))
//    }
    
}
@private 
c_console_log :: proc"c"(category: log_category, text: cstring){
    if category > log_level{
        return
    }

    context = runtime.default_context()
    output_file := os.stderr
    prefix := ""
    hour, min, second := time.clock(time.now())
      
    switch category {
      case log_category.VERBOSE: prefix = "[\033[34mVERBSE\033[0m]["
      case log_category.INFO:    prefix = "[\033[34mINFO\033[0m]  ["
      case log_category.WARNING: prefix = "[\033[93mWARN\033[0m]  ["
      case log_category.ERROR:   prefix = "[\033[31mERROR\033[0m] ["
      case log_category.CRITICAL:prefix = "[\033[31mCRTCAL\033[0m]["
      case log_category.DEBUG:   prefix = "[\033[35mDEBUG\033[0m] ["
    }
    sync.guard(&log_mutex)
    fmt.fprint(output_file, prefix)
    fmt.fprintf(output_file, "%02i:%02i:%02i] ", hour, min, second);
    fmt.fprintln(output_file, text)
}

@private
interface_set :: proc"c"(name : string, interface: module_interface){
    if value, ok := &modules[name]; ok { 
        value.interface = interface
    }
}
@private
version_set :: proc"c"(name : string, version: version){
    if value, ok := &modules[name]; ok { 
        value.module_version = version
    }
}

@private
interface_get :: proc"c"(name : string) -> module_interface{
    return modules[name].interface
}

@private
version_get :: proc"c"(name : string) -> version{
    return modules[name].module_version
}


@private
code_inject :: proc"c"(file: os.Handle, offset: i64 , padding: int, procedure: uintptr){
    call_code := []u8{
        0x68,
        u8(procedure),
        u8(procedure >> 8),
        u8(procedure >> 16),
        u8(procedure >> 24),
        0xc3
    } 
    
    context = runtime.default_context()
    os.seek(file, offset, os.SEEK_SET)
    os.write(file, call_code)
    for i := 0; i < padding; i+=1{
        os.write_byte(file, 0x90)   
    } 
}

@private
quit :: proc"c"(status: int){ 

    console_log(.INFO, "saving configuration...")
    {
        context = runtime.default_context()

        config_file, error := os.open("config.txt", os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o777)

        if error == os.ERROR_NONE{
            for key in configuration{
                config := configuration[key]
                switch c in config.value{
                    case i64:    fmt.fprintfln(config_file, "%s=%l", key, c)
                    case b8:     fmt.fprintfln(config_file, "%s=%b", key, c)
                    case f64:    fmt.fprintfln(config_file, "%s=%f", key, c)
                    case string: fmt.fprintfln(config_file, "%s=%s", key, c)
                }
            }
            os.close(config_file)
        }else{
            console_log(.ERROR, "could not open config.txt file, %i", os.get_last_error())
        }
    }

    os.exit(status)        
}


