package main

import "C"
import (
	"io/ioutil"
	"os"
	"path/filepath"

	"github.com/evanw/esbuild/pkg/api"
)

//export esbuild_transform
func esbuild_transform(source *C.char, source_len C.int, loader *C.char) *C.char {
	// Convert C strings to Go
	sourceCode := C.GoStringN(source, source_len)
	loaderStr := C.GoString(loader)

	// Map loader string to esbuild.Loader enum
	var loaderType api.Loader
	switch loaderStr {
	case "ts":
		loaderType = api.LoaderTS
	case "tsx":
		loaderType = api.LoaderTSX
	case "js":
		loaderType = api.LoaderJS
	case "jsx":
		loaderType = api.LoaderJSX
	default:
		loaderType = api.LoaderTS
	}

	// Transform TypeScript to JavaScript
	result := api.Transform(sourceCode, api.TransformOptions{
		Loader:            loaderType,
		Target:            api.ES2020,
		Format:            api.FormatCommonJS,
		MinifyWhitespace:  false,
		MinifyIdentifiers: false,
		MinifySyntax:      false,
		Sourcemap:         api.SourceMapNone,
	})

	// Check for errors
	if len(result.Errors) > 0 {
		errorMsg := result.Errors[0].Text
		return C.CString(errorMsg)
	}

	// Return transpiled code
	return C.CString(string(result.Code))
}

//export esbuild_build
func esbuild_build(entry_point *C.char, out_file *C.char) *C.char {
	// Convert C strings to Go
	entryPath := C.GoString(entry_point)
	outPath := C.GoString(out_file)

	// Get absolute path for entry point
	absEntry, err := filepath.Abs(entryPath)
	if err != nil {
		return C.CString("Error: " + err.Error())
	}

	// Create temp directory for output if needed
	outDir := filepath.Dir(outPath)
	if err := os.MkdirAll(outDir, 0755); err != nil {
		return C.CString("Error creating output directory: " + err.Error())
	}

	// Bundle TypeScript files using Build API
	result := api.Build(api.BuildOptions{
		EntryPoints: []string{absEntry},
		Outfile:     outPath,
		Bundle:      true,              // Bundle all imports into single file
		Write:       true,              // Write to disk
		Target:      api.ES2020,        // ES2020 target
		Format:      api.FormatCommonJS, // CommonJS output
		Platform:    api.PlatformNode,  // Node.js platform
		MinifyWhitespace: false,
		MinifyIdentifiers: false,
		MinifySyntax:     false,
		Sourcemap:        api.SourceMapNone,
		LogLevel:         api.LogLevelWarning,
	})

	// Check for errors
	if len(result.Errors) > 0 {
		errorMsg := result.Errors[0].Text
		return C.CString("Error: " + errorMsg)
	}

	// Read the bundled output
	bundled, err := ioutil.ReadFile(outPath)
	if err != nil {
		return C.CString("Error reading output: " + err.Error())
	}

	// Return bundled JavaScript
	return C.CString(string(bundled))
}

func main() {}
