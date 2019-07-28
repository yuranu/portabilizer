# Portabilizer

A simple script that packs an ELF binary, alongside its dependencies, into a single executable archive.

## Rationale

Dependency hell is nothing new in Linux world. Even the most basic hello world executable most likelly has at least one dependency - libc.

In order to be able to port an executable compiled on a source system to a different target system, one of the following must be true:

1. You can recompile the executable directly on the target system.

.. or

2. All dependencies of the compiled executable must exist on the target system, in compatible versions.

The best way and the cleanest way is of cause to build your executable for the target system or directly on the target system, and portabilizer is **by no means** a replacement for a clean work flow.

But, what if ...

* ... you don't have the source code of the executable?
* ... you do have the source code, but cannot compile it (for example its is remote clien's machine)?
* ... the target system does not provide some of the dependencies (and there is no way to install it)?
* ... target system provides incompatible versions of dependencies (and you cannot upgrade it)?

These are just examples of the cases when you might want a portable executable. These exception cases is what portabilize is trying to solve.

Instead of messing with dependecy hell, just pack all the dependencies in one executable archive, and run anywhere.

## Usage

To create a portable archive:

    portzr.sh -b my_binary_executable -o my_portable_archive

Then, just run it, anywhere:
    
    ./my_portable_archive
    
That's it.

## A little more complex usage

Lets say you wish have an executable exe_main that lauches 2 other executables exe_main and exe_B. You can pack all of them into one archive, using:

    portzr.sh -b exe_main -b exe_A -b exe_B -o arch.port
    
Now assume all your exes are also using a database data.sqlite3, that you want to pack alongside with them. So you can say:

    portzr.sh -b exe_main -b exe_A -b exe_B -f data.sqlite3 -o arch.port
    
Now maybe you do not want to invoke exe_main directly. You have a bash script, exe.sh, that does it. So add this script to the archive, and specify it as an entry point:

    portzr.sh -b exe_main -b exe_A -b exe_B -f data.sqlite3 -f exe.sh -e exe.sh -o arch.port
    
During the execution of exe_main, exe.sh, or any other exe, all the packed files are accessible from a single directory. For example, to access exe_main from within exe.sh, use:

    $(dirname $0)/exe_main

## How it works

The process is actually very simple, and I was amazed at first I could not find a free tool that does it, that is not architecture specific.

* First, read ELF header to find out what dynamic linker the executable wants to use.
* Then use the dynamic linker to resolve all .so dependencies.
* Next, pack the linker, the libs and the exe into a simple self extracting tar.
* ...
* PROFIT

On the target system, extract the tar into temp location and run the entry point.

* Poratbilizer will respect $TMPDIR environment variable in case you want to tweak the process, for example run form specific tmpfs mount point.

### Why packing the linker?

If an exe was compiled using a newer libc on an older version, naturally it will not work, even if you don't use any new API. Hence libc is one of the libraries you have to pack with you.

Dynamic linker (typically /lib64/ld-linux-x86-64.so.2) is coupled with libc. Using dynamic linker from older system on the new libc (which we have to pack) will result in errors. Hence the dynamic linker must be packed too, and the exe must be run with this specific dynamic linker.

### Can't you do it wihtout tmp dir?

Well you can. Though linux does not provide an API for exec system call that is not from file standalone, there is some interesting trick [here](https://magisterquis.github.io/2018/03/31/in-memory-only-elf-execution.html) - a way to execute ELF directly from RAM, which can be used for this. This trick could be used to the launch dynamic linker without extracting the tar.

The problem is that it requires memfd_create system call, which is available since kernel 3.17. This is pretty old, but the problem is that many entrprise system today still use stone age kernels, that do not provide this bronze age system call.

Regretfully, these systems are exactly the main use case for portabilizer. Hence I decided to simply use tmp dir, though I am planning to make a version without tmp dir for newer systems.

## Caveats

1. Licensing - portabilizer will not concern itself with licensing. If it needs some lib, it will just grab it. This lib may turn out to be some proprietary AI library worth 100K that you are not allowed to redistribute. Don't care, not my concern. Dealing with licensing is your reponsibility.

2. Exe name and location mangling - your executable may have different location when run with portabilizer. Not talking about working directory, the directory it is run from - that does not change. What changes is basically is the value of argv[0]. Hence if you rely somehow on exe file to be in some specific location, you may have a problem.

## License

Portabilizer is ditributed under MIT license, i.e. in short you are free to use it however you want.
