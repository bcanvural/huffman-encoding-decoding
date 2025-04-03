# Huffman Encoding and Decoding

This project implements a file compression tool using Huffman encoding and decoding algorithms using the Zig programming language.

## Requirements

- Zig version 0.14.0

Ensure you have the correct version of Zig installed before building and running the project.

## Building the Project

To build the project, run the following command:

```bash
zig build
```

## Running the Project

After building, you can run the project using:

```bash
#compress:
zig build run -- -c inputfilename outputfilename
#decompress:
zig build run -- -d inputfilename outputfilename #where intputfilename is the outputfilename of the previous command
```

-c for compression, -d for decompression

## License

This project is licensed under the Apache License.
