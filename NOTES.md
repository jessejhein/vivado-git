* Vivado doesn't seem to like spaces in the directory path. Don't do it!
* On Windows (and cygwin), this apparently includes Documents => "My Documents"
* Internally to the script, you will see "/" for the directory paths. Vivado uses these (even on windows, where the path will be, for example, "E:/Xilinx/Vivado")
* Cygwin seems to pass things through to Vivado when calling it directly.
  * The settings64.sh leaves badly formatted (windows formatted) directories in the path variable. However, if you fix them and call vivado, it breaks as it can't find libraries.
  * Without fixing them you, of course, can't call vivado from the command line (or the script). So a custom search routine in perl was written.
  * However, this still doesn't work, as if the repository is on another drive from the xilinx tools, it breaks again. So the tool now uses the "cmd.exe" to call vivado in cygwin.
  * However, due to the point above about slashes, the relative paths are fine from vivado to cygwin. Only need fixed for absolute paths.
