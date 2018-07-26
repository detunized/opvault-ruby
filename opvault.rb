#!/usr/bin/env ruby

require "json"

def open_vault path
    profile = load_profile path
    folders = load_folders path

    ap load_band path, "d"
end

def make_filename path, filename
    File.join path, "default", filename
end

def load_profile path
    filename = make_filename path, "profile.js"
    load_js_as_json filename, "var profile=", ";"
end

def load_folders path
    filename = make_filename path, "folders.js"
    load_js_as_json filename, "loadFolders(", ");"
end

def load_band path, index
    filename = make_filename path, "band_#{index.upcase}.js"
    load_js_as_json filename, "ld(", ");"
end

def load_js_as_json filename, prefix, suffix
    content = File.read filename

    fail "Unsupported format: must start with #{prefix}" if !content.start_with? prefix
    fail "Unsupported format: must end with #{suffix}" if !content.end_with? suffix

    JSON.load content[prefix.size...-suffix.size]
end

open_vault "#{ENV["HOME"]}/Downloads/opvault.opvault"
