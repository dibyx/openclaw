import path from "node:path";
console.log(path.win32.normalize("/bin/bash") === "/bin/bash");
console.log(path.win32.normalize("/bin/bash"));
console.log(path.win32.isAbsolute("/bin/bash"));
