#!/usr/bin/env ruby

require "json"

def open_vault path
    profile = load_profile path
    folders = load_folders path
    items = load_items path

    ap items.keys
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

def load_items path
    items = {}

    "0123456789ABCDEF".each_char do |i|
        filename = make_filename path, "band_#{i}.js"
        if File.exist? filename
            items.merge! load_band filename
        end
    end

    items
end

def load_band filename
    load_js_as_json filename, "ld(", ");"
end

def load_js_as_json filename, prefix, suffix
    content = File.read filename

    if !content.start_with? prefix
        fail "Unsupported format: must start with #{prefix}"
    end

    if !content.end_with? suffix
        fail "Unsupported format: must end with #{suffix}"
    end

    JSON.load content[prefix.size...-suffix.size]
end

open_vault "#{ENV["HOME"]}/Downloads/opvault.opvault"
