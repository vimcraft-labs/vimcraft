/// Hermes C API - Shared Import
/// IMPORTANT: This file must be imported by all JSI modules
/// DO NOT use @cImport in individual modules - it creates incompatible types

// Single centralized import of Hermes C API
pub const c = @cImport({
    @cInclude("system/jsi/hermes_c_api.h");
});
