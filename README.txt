The code in this folder is written in the D programming language, and has been tested to work with DMD v2.063.2, on linux and Windows in a 64-bit environment.

The included binary is for linux 64-bit, (note it may not match your glibc version).

You can get the D toolchain from http://dlang.org/download.html.

Compile the benchmark by issuing the command
$ rdmd -O -inline -release -noboundscheck --build-only benchmark

Adding the -debug flag will cause the program to print out more information when populating the bloomier filters.

and run the benchmark by calling
$ ./benchmark <file#> <times>

<file#> refers to the number of the ngram file. If no argument is given, it defaults to 1, or the 1k ngram file.

You may need to adjust the filenames in the array at the top of benchmark.d to match your filesystem.

Only the 1k ngram file is included in the data folder, because the other files are too large.

Also included in the data folder is a spreadsheet with the full benchmark results and charts.
