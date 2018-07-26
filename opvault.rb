#!/usr/bin/env ruby

require "json"

def open_vault path
    profile = parse_profile File.join(path, "default/profile.js")
    folders = parse_folders File.join(path, "default/folders.js")
end

def parse_profile filename
    load_js_as_json filename, "var profile=", ";"
end

def parse_folders filename
    load_js_as_json filename, "loadFolders(", ");"
end

def load_js_as_json filename, prefix, suffix
    content = File.read filename

    fail "Unsupported format: must start with #{prefix}" if !content.start_with? prefix
    fail "Unsupported format: must end with #{suffix}" if !content.end_with? suffix

    JSON.load content[prefix.size...-suffix.size]
end

open_vault "#{ENV["HOME"]}/Downloads/opvault.opvault"
