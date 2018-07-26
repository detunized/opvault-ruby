#!/usr/bin/env ruby

require "base64"
require "json"
require "openssl"

def open_vault path, password
    profile = load_profile path
    folders = load_folders path
    items = load_items path

    key, mac = derive_key_mac profile, password
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
        raise "Unsupported format: must start with #{prefix}"
    end

    if !content.end_with? suffix
        raise "Unsupported format: must end with #{suffix}"
    end

    JSON.load content[prefix.size...-suffix.size]
end

def decode64 base64
    Base64.decode64 base64
end

def derive_key_mac profile, password
    salt = decode64 profile["salt"]
    iterations = profile["iterations"]
    key_mac = pbkdf2_sha512 password, salt, iterations, 64

    [key_mac[0, 32], key_mac[32, 32]]
end

def pbkdf2_sha512 password, salt, iterations, size
    OpenSSL::PKCS5.pbkdf2_hmac password, salt, iterations, size, "sha512"
end

open_vault "#{ENV["HOME"]}/Downloads/opvault.opvault", "password"
