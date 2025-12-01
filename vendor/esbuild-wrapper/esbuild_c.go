package main

import "C"
import (
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"

	"github.com/evanw/esbuild/pkg/api"
)

// =============================================================================
// Hermes Compatibility Layer
// =============================================================================
//
// BACKGROUND:
// Hermes (React Native's JS engine) has a fundamental limitation with ES6 block
// scoping (github.com/facebook/hermes/issues/575). Object.defineProperty getters
// defined in a loop all resolve to the same value (the last iteration's value).
//
// This breaks esbuild's CommonJS interop patterns (__export, __copyProps) which
// use lazy getters for tree-shaking compatibility.
//
// WHY STRING REPLACEMENT:
// - No official esbuild option to avoid these patterns
// - esbuild's --target=hermes doesn't help (can't downlevel const/let)
// - This is the standard workaround (used by @rnx-kit/metro-serializer-esbuild)
// - esbuild's output format is deterministic (same input → same output)
//
// MAINTENANCE:
// If esbuild changes output format, transforms will silently fail (no match).
// Run TestHermesTransforms() to verify patterns still match current esbuild.
//
// References:
// - github.com/facebook/hermes/issues/575 (the root cause)
// - github.com/evanw/esbuild/issues/2365 (esbuild's hermes target discussion)
// =============================================================================

// HermesTransform represents a single find-replace transformation
type HermesTransform struct {
	Name        string // For logging/debugging
	Description string // Human-readable description
	Find        string // Pattern to find
	Replace     string // Replacement pattern
}

// HermesTransformSet is a collection of related transforms
type HermesTransformSet struct {
	Name       string
	Transforms []HermesTransform
}

// Apply applies all transforms in the set to the code
func (ts *HermesTransformSet) Apply(code string) string {
	result := code
	for _, t := range ts.Transforms {
		if strings.Contains(result, t.Find) {
			result = strings.Replace(result, t.Find, t.Replace, 1)
		}
	}
	return result
}

// =============================================================================
// Transform Definitions
// =============================================================================

// buildExportTransforms creates transforms for esbuild's __export pattern variants
// esbuild may rename __export to __export2, __export3, etc. on naming conflicts
func buildExportTransforms() HermesTransformSet {
	transforms := make([]HermesTransform, 0, 10)

	for i := 0; i <= 9; i++ {
		var name string
		if i == 0 {
			name = "__export"
		} else {
			name = "__export" + string(rune('0'+i))
		}

		// Original (broken in Hermes):
		//   var __export = (target, all) => {
		//     for (var name in all)
		//       __defProp(target, name, { get: all[name], enumerable: true });
		//   };
		//
		// Fixed (direct assignment - calls getters immediately):
		//   var __export = (target, all) => {
		//     for (var name in all)
		//       target[name] = all[name]();
		//   };

		transforms = append(transforms, HermesTransform{
			Name:        name,
			Description: "Fix " + name + " lazy getter pattern",
			Find:        "var " + name + " = (target, all) => {\n  for (var name in all)\n    __defProp(target, name, { get: all[name], enumerable: true });\n};",
			Replace:     "var " + name + " = (target, all) => {\n  for (var name in all)\n    target[name] = all[name]();\n};",
		})
	}

	return HermesTransformSet{
		Name:       "ExportPattern",
		Transforms: transforms,
	}
}

// buildCopyPropsTransform creates the transform for esbuild's __copyProps pattern
func buildCopyPropsTransform() HermesTransformSet {
	// Original (broken in Hermes):
	//   var __copyProps = (to, from, except, desc) => {
	//     if (from && typeof from === "object" || typeof from === "function") {
	//       for (let key of __getOwnPropNames(from))
	//         if (!__hasOwnProp.call(to, key) && key !== except)
	//           __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
	//     }
	//     return to;
	//   };
	//
	// Fixed (direct assignment):
	//   var __copyProps = (to, from, except, desc) => {
	//     if (from && typeof from === "object" || typeof from === "function") {
	//       for (let key of __getOwnPropNames(from))
	//         if (!__hasOwnProp.call(to, key) && key !== except)
	//           to[key] = from[key];
	//     }
	//     return to;
	//   };

	return HermesTransformSet{
		Name: "CopyPropsPattern",
		Transforms: []HermesTransform{
			{
				Name:        "__copyProps",
				Description: "Fix __copyProps lazy getter pattern (used by __toCommonJS)",
				Find:        "var __copyProps = (to, from, except, desc) => {\n  if (from && typeof from === \"object\" || typeof from === \"function\") {\n    for (let key of __getOwnPropNames(from))\n      if (!__hasOwnProp.call(to, key) && key !== except)\n        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });\n  }\n  return to;\n};",
				Replace:     "var __copyProps = (to, from, except, desc) => {\n  if (from && typeof from === \"object\" || typeof from === \"function\") {\n    for (let key of __getOwnPropNames(from))\n      if (!__hasOwnProp.call(to, key) && key !== except)\n        to[key] = from[key];\n  }\n  return to;\n};",
			},
		},
	}
}

// allHermesTransforms returns all registered transform sets
func allHermesTransforms() []HermesTransformSet {
	return []HermesTransformSet{
		buildExportTransforms(),
		buildCopyPropsTransform(),
		// Add new transform sets here as needed
	}
}

// ApplyHermesCompatibility applies all Hermes compatibility transforms to bundled code
func ApplyHermesCompatibility(code string) string {
	result := code
	for _, ts := range allHermesTransforms() {
		result = ts.Apply(result)
	}
	return result
}

// =============================================================================
// esbuild C API
// =============================================================================

//export esbuild_transform
func esbuild_transform(source *C.char, source_len C.int, loader *C.char) *C.char {
	sourceCode := C.GoStringN(source, source_len)
	loaderStr := C.GoString(loader)

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

	result := api.Transform(sourceCode, api.TransformOptions{
		Loader:            loaderType,
		Target:            api.ES2020,
		Format:            api.FormatCommonJS,
		MinifyWhitespace:  false,
		MinifyIdentifiers: false,
		MinifySyntax:      false,
		Sourcemap:         api.SourceMapNone,
	})

	if len(result.Errors) > 0 {
		return C.CString(result.Errors[0].Text)
	}

	return C.CString(string(result.Code))
}

//export esbuild_build
func esbuild_build(entry_point *C.char, out_file *C.char) *C.char {
	entryPath := C.GoString(entry_point)
	outPath := C.GoString(out_file)

	// Resolve to absolute path
	absEntry, err := filepath.Abs(entryPath)
	if err != nil {
		return C.CString("Error: " + err.Error())
	}

	// Resolve symlinks for proper relative import resolution
	if realEntry, err := filepath.EvalSymlinks(absEntry); err == nil {
		absEntry = realEntry
	}

	// Ensure output directory exists
	if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
		return C.CString("Error creating output directory: " + err.Error())
	}

	// Bundle with esbuild
	result := api.Build(api.BuildOptions{
		EntryPoints:       []string{absEntry},
		Outfile:           outPath,
		Bundle:            true,
		Write:             true,
		Target:            api.ES2020,
		Format:            api.FormatCommonJS,
		Platform:          api.PlatformNeutral,
		MinifyWhitespace:  false,
		MinifyIdentifiers: false,
		MinifySyntax:      false,
		Sourcemap:         api.SourceMapNone,
		LogLevel:          api.LogLevelWarning,
		// Map globals to globalThis.* for CommonJS module scope
		Define: map[string]string{
			"vim":                    "globalThis.vim",
			"console":                "globalThis.console",
			"setTimeout":             "globalThis.setTimeout",
			"setInterval":            "globalThis.setInterval",
			"clearTimeout":           "globalThis.clearTimeout",
			"clearInterval":          "globalThis.clearInterval",
			"fs":                     "globalThis.fs",
			"process":                "globalThis.process",
			"fetch":                  "globalThis.fetch",
			"requestAnimationFrame":  "globalThis.requestAnimationFrame",
			"cancelAnimationFrame":   "globalThis.cancelAnimationFrame",
			"performance":            "globalThis.performance",
		},
	})

	if len(result.Errors) > 0 {
		return C.CString("Error: " + result.Errors[0].Text)
	}

	// Read bundled output
	bundled, err := ioutil.ReadFile(outPath)
	if err != nil {
		return C.CString("Error reading output: " + err.Error())
	}

	// Apply Hermes compatibility transforms
	fixed := ApplyHermesCompatibility(string(bundled))

	// Write fixed bundle back
	if err := ioutil.WriteFile(outPath, []byte(fixed), 0644); err != nil {
		return C.CString("Error writing output: " + err.Error())
	}

	return C.CString(fixed)
}

func main() {}
