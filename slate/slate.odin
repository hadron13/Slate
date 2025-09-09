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
import "core:sys/posix"

//import "../tracy"

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
        string, i64, f64, bool 
    }
}

module_interface :: distinct rawptr

@private
module :: struct{
    name              : string,
    version           : version,
    interface         : module_interface,
    library           : dynlib.Library,
    dependencies      : []string,
}

@private
task_proc :: proc"c"(core: ^core_interface, data: rawptr)

@private
task_status :: enum{
    WAITING, RUNNING, DONE
}

@private
task :: struct{
    name      : string,
    status    : task_status,
    repeatable: bool,
    user_data : rawptr,
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
    config_get_bool     : proc"c"(key : string, default : bool = false) -> bool,
    //LOGGING   
    log         : proc"c"(category: log_category, format: string, args: ..any, module := MODULE, location := #caller_location),
    c_log       : proc"c"(category: log_category, text: cstring),
    //MODULES
    module_set_interface: proc"c"(name: string, interface: module_interface),  
    module_get_interface: proc"c"(name: string) -> module_interface,      
    module_get_version  : proc"c"(name: string) -> version,
    module_reload       : proc"c"(name: string), // hot-reloads module, optionally calling a reload() procedure   
    //TASKS
    task_add_pool       : proc"c"(name: string, threads: u32),
    task_add_repeated   : proc"c"(name: string, pool: string, task: task_proc, user_data: rawptr,  dependencies: []string),
    task_add_once       : proc"c"(name: string, pool: string, task: task_proc, user_data: rawptr,  dependencies: []string),
    //MISC 
    on_quit             : proc"c"(callback : proc"c"(status : int)),
    quit                : proc"c"(status: int) -> ! 
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
quit_callbacks: [dynamic]proc"c"(int)
@private 
core_context  : runtime.Context

when ODIN_DEBUG{
    @private
    track: mem.Tracking_Allocator
}
@private
main :: proc() {
    log_level = .DEBUG
    //tracy.SetThreadName("main");
    
    posix.signal(.SIGINT, proc"c"(sig : posix.Signal){
        // quit(-1)
        os.exit(-1)
    })

    when ODIN_DEBUG{
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
    }

    when ODIN_OPTIMIZATION_MODE == .Speed || ODIN_OPTIMIZATION_MODE == .Aggressive{
        config_set({"log_level", "WARNING"})
    }
    core_context = context

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
        module_set_interface,
        module_get_interface,
        module_get_version,
        nil,
        task_add_pool,
        task_add_repeated,
        task_add_once,
        on_quit,
        quit,
    }

    console_log(.INFO, "starting")
    
    task_add_pool("main", u32(os.processor_core_count()-2))
    
    cwd := os.get_current_directory()
    
    console_log(.INFO, "loading configs")
    {
        config_file, ok := os.read_entire_file("config.txt")
        if ok{
            defer delete(config_file)
            iterator := string(config_file)

            for config in strings.split_lines_iterator(&iterator){
                config_parse(config[:len(config)])
            }
        }
        for arg in os.args{
            if arg[0] == '-' && strings.contains_rune(arg, '=') {
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
            modules[listed_mod.name] = {name=listed_mod.name, library=mod_lib}
        
            load_proc := cast(proc"c"(^core_interface) -> version) load_ptr

            mod_version := load_proc(&interface)

            (&modules[listed_mod.name]).version = mod_version
        }
    }
    for key, &pool in task_pools{
        task_pool_run(&pool)
    }
    task_runner_thread(&task_pools["main"])


}


@private
task_add_pool :: proc"c"(name: string, threads: u32){
    context = core_context
    console_log(.INFO, "creating pool %s with %i threads", name, threads)
    
    task_pools[name] = {}
    pool := &task_pools[name]
    pool.name = name 
    pool.is_sorted = true
    pool.is_running= true 
    pool.task_index= 0

    pool.threads = make([]^thread.Thread, max(threads, 1))
    topological_sort.init(&pool.task_sorter)
}

task_pool_run :: proc "c"(pool : ^task_pool){
    context = core_context
    for _, i in pool.threads{
        pool.threads[i] = thread.create_and_start_with_data(pool, task_runner_thread)
	}
}

@private
task_add_internal :: proc"c"(name: string, pool: string, task: task_proc, user_data: rawptr, repeat: bool,  dependencies: []string){
    context = core_context
    
    if(task == nil){
        console_log(.ERROR, "Null procedure in task '%s', pool %s", name, pool)
        return
    }
    tpool := &task_pools[pool]
    name := strings.clone(name)
    
    sync.guard(&tpool.mutex) 
    tpool.tasks[name] = {
        name=name,
        status=.WAITING,
        repeatable=repeat,
        user_data=user_data,
        procedure=task, 
        dependencies=slice.clone(dependencies)
    }

    topological_sort.add_key(&tpool.task_sorter, name)
    if(dependencies != nil){
        tpool.is_sorted = false
        for dependency in tpool.tasks[name].dependencies{
            if !(dependency in tpool.tasks){
                console_log(.WARNING, "task '%s' depends on unknown task '%s'", name, dependency)
            }
            topological_sort.add_dependency(&tpool.task_sorter, name, dependency)
        }
    }else{
        append(&tpool.tasks_sorted, tpool.tasks[name].name)
    }
}

@private
task_add_repeated :: proc"c"(name: string, pool: string, task: task_proc, user_data: rawptr,  dependencies: []string){
    task_add_internal(name, pool, task, user_data, true, dependencies)
}
@private
task_add_once:: proc"c"(name: string, pool: string, task: task_proc, user_data: rawptr,  dependencies: []string){
    task_add_internal(name, pool, task, user_data, false, dependencies)
}

@private
task_runner_thread :: proc(pool_ptr : rawptr){
    pool := cast(^task_pool)pool_ptr
    
    console_log(.INFO, "starting thread %i from pool %s", os.current_thread_id(), pool.name)
    
    name := fmt.ctprintf("%s:%i", pool.name, os.current_thread_id())

    //tracy.SetThreadName(name)

    for pool.is_running {
        task_execute(pool)
    }
}



@private
task_execute :: proc(pool: ^task_pool){ 
    sync.guard(&pool.mutex)
    
    if !pool.is_sorted{
        pool.is_sorted = true 
        //tracy.ZoneN("Task Sorting")
        delete(pool.tasks_sorted)
        pool.tasks_sorted, _ = topological_sort.sort(&pool.task_sorter)

        for key, &relation in pool.task_sorter.relations{
            for dependent, val in relation.dependents{
                dependent_relation := &pool.task_sorter.relations[dependent]
                dependent_relation.dependencies += 1
            }
        }
    }
    if len(pool.tasks_sorted) == 0 {
        time.sleep(500 * time.Microsecond)
        return
    } 
    
    task_to_run : string = ""

    no_tasks_left := true
    unbroken_done := true
       
    {
        //tracy.ZoneN("Task Search")
        
        task_search:
        for name in pool.tasks_sorted[pool.task_index:]{
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
            task_to_run = name
            break
        }
    }
    // console_log(.DEBUG, "------------")
    // console_log(.DEBUG, "pool %s - index %i", pool.name, pool.task_index)
    // for name in pool.tasks_sorted{
    //     console_log(.DEBUG, "%s \t- %s", name, pool.tasks[name].status==.WAITING?"waiting":pool.tasks[name].status==.RUNNING?"running":"done")
    // }
    
    if no_tasks_left{
        for name in pool.tasks_sorted{
            task := &pool.tasks[name]

            if task.status != .DONE do continue

            if task.repeatable{
                task.status = .WAITING
                continue
            }    
            relations := &pool.task_sorter.relations[name]
            for key, _ in relations.dependents{
                (&pool.task_sorter.relations[key]).dependencies -= 1
            }
            delete_key(&pool.task_sorter.relations, name)
            pool.is_sorted = false
            continue
        }
        pool.task_index = 0
        return
    }
    if task_to_run == "" do return
    
    // start := time.tick_now()
    sync.unlock(&pool.mutex)
    {
        //tracy.ZoneN(fmt.tprintf("Task %s", task_to_run))
        pool.tasks[task_to_run].procedure(&interface, pool.tasks[task_to_run].user_data)
    }
    sync.lock(&pool.mutex)
    
    // console_log(.DEBUG, "%s took %i", task_to_run, time.tick_since(start))

    (&pool.tasks[task_to_run]).status = .DONE
}


@private
config_set :: proc"c"(cfg : config) {
    @(static) mutex : sync.Mutex
    sync.guard(&mutex)
    context = core_context
    if str, is_string := cfg.value.(string); is_string{
        configuration[strings.clone(cfg.key)] = {cfg.key, strings.clone(str)} 
        return
    }
    configuration[strings.clone(cfg.key)] = cfg
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
config_get_bool     :: proc"c"(key : string, default : bool = false)  -> bool       {return (configuration[key] or_else (config){"", default}).value.(bool)      or_else default}
     
    
@private
config_parse :: proc(text : string) {
    string_portions, _ := strings.split(text, "=")
    if len(string_portions) < 2{
        return
    }
    console_log(.DEBUG, "%s - %s", string_portions[0], string_portions[1])
    key := string_portions[0]
    value_string := string_portions[1]

    if strings.contains_rune(value_string, '"'){ 
        config_set({key, value_string})
        return
    }
    if strings.compare(value_string, "true") == 0{
        config_set({key, true}) 
        return
    }
    if strings.compare(value_string, "false")== 0{
        config_set({key, false}) 
        return
    }

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

@private
log_mutex : sync.Mutex
@private
log_file  : os.Handle

@private
console_log :: proc"c"(category: log_category, format: string, args: ..any, module := MODULE, location := #caller_location) {
    if category > log_level{
        return
    }

    context = core_context
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

    context = core_context
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
module_set_interface :: proc"c"(name : string, interface: module_interface){
    if value, ok := &modules[name]; ok { 
        value.interface = interface
    }
}

@private
module_get_interface :: proc"c"(name : string) -> module_interface{
    return modules[name].interface
}

@private
module_get_version :: proc"c"(name : string) -> version{
    return modules[name].version
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
    
    context = core_context
    os.seek(file, offset, os.SEEK_SET)
    os.write(file, call_code)
    for i := 0; i < padding; i+=1{
        os.write_byte(file, 0x90)   
    } 
}

@private 
on_quit :: proc"c"(callback : proc"c"(status : int)){
    context = core_context
    append(&quit_callbacks, callback)
}


@private
quit :: proc"c"(status: int) -> !{ 
    context = core_context
    console_log(.INFO, "saving configuration...")
    {
        context = core_context

        config_file, error := os.open("config.txt", os.O_CREATE | os.O_WRONLY | os.O_TRUNC, 0o777)
        if error == os.ERROR_NONE{
            for key in configuration{
                config := configuration[key]
                switch c in config.value{
                    case i64:    fmt.fprintfln(config_file, "%s=%l", key, c)
                    case f64:    fmt.fprintfln(config_file, "%s=%f", key, c)
                    case bool:   fmt.fprintfln(config_file, "%s=%s", key, c?"true":"false")
                    case string: {
                        fmt.fprintfln(config_file, "%s=%s", key, c)
                        delete(c)
                    }
                }
            }
            os.close(config_file)
        }else{
            console_log(.ERROR, "could not open config.txt file, %i", os.get_last_error())
        }
    } 
    for callback in quit_callbacks{
        callback(status)
    }

    for key, &pool in task_pools{
        pool.is_running = false
        time.sleep(30 * time.Millisecond)
        for key, task in pool.tasks{
            delete(task.name)
            delete(task.dependencies)
        }
        topological_sort.destroy(&pool.task_sorter)
        delete(pool.tasks)
        delete(pool.tasks_sorted)
        delete(pool.threads)
    }
    delete(task_pools)
    

    when ODIN_DEBUG{
        for _, leak in track.allocation_map {
            console_log(.DEBUG,"%v leaked %m\n", leak.location, leak.size)
        }
    }

    os.exit(status)        
}


