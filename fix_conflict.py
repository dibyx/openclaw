import re

with open('src/memory/manager-sync-ops.ts', 'r') as f:
    content = f.read()

content = re.sub(
    r'<<<<<<< HEAD\n\s*const existingHash = dbHashes\.get\(entry\.path\);\n=======\n\s*// Use the in-memory map instead of a DB query\n\s*const existingHash = existingFileMap\.get\(entry\.path\);\n\n>>>>>>> origin/main',
    '      const existingHash = existingFileMap.get(entry.path);',
    content
)

with open('src/memory/manager-sync-ops.ts', 'w') as f:
    f.write(content)
