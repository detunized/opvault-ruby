#!/usr/bin/env ruby

require "base64"
require "json"
require "openssl"

class KeyMac < Struct.new :key, :mac_key
    def self.from_str s
        new s[0, 32], s[32, 32]
    end
end

def open_vault path, password
    profile = load_profile path
    folders = load_folders path
    items = load_items path

    kek = derive_kek profile, password

    master_key = decrypt_master_key profile, kek
    overview_key = decrypt_overview_key profile, kek

    decrypt_item_overviews! items, overview_key

    ap items
end

def decrypt_item_overviews! items, key
    items.values.each do |i|
        i["o"] = JSON.load decrypt_base64_opdata i["o"], key
    end
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

def derive_kek profile, password
    salt = decode64 profile["salt"]
    iterations = profile["iterations"]
    KeyMac.from_str pbkdf2_sha512 password, salt, iterations, 64
end

def decrypt_master_key profile, kek
    decrypt_key profile, "masterKey", kek
end

def decrypt_overview_key profile, kek
    decrypt_key profile, "overviewKey", kek
end

def decrypt_key profile, name, kek
    raw = decrypt_base64_opdata profile["overviewKey"], kek
    KeyMac.from_str sha512 raw
end

def decrypt_base64_opdata blob_base64, key
    blob = decode64 blob_base64
    decrypt_opdata blob, key
end

def decrypt_opdata blob, key
    if blob.size < 64
        raise "Opdata01 container is corrupted: too short"
    end

    header = blob[0, 32]

    if !header.start_with? "opdata01"
        raise "Opdata01 container is corrupted: missing header"
    end

    length = header[8, 8].unpack("V")[0]
    iv = header[16, 16]
    padding = 16 - length % 16

    if blob.size != 32 + padding + length + 32
        raise "Opdata01 container is corrupted: invalid length"
    end

    ciphertext = blob[header.size, padding + length]
    stored_tag = blob[header.size + ciphertext.size, 32]
    computed_tag = hmac_sha256 key.mac_key, header + ciphertext

    if computed_tag != stored_tag
        raise "Opdata01 container is corrupted: tag doesn't match"
    end

    plaintext = decrypt_aes256 ciphertext, iv, key.key
    plaintext[padding, length]
end

#
# Utils
#

def decode64 base64
    Base64.decode64 base64
end

#
# Crypto
#

def pbkdf2_sha512 password, salt, iterations, size
    OpenSSL::PKCS5.pbkdf2_hmac password, salt, iterations, size, "sha512"
end

def sha512 message
    Digest::SHA512.digest message
end

def hmac_sha256 key, message
    OpenSSL::HMAC.digest "sha256", key, message
end

def decrypt_aes256 ciphertext, iv, key
    aes = OpenSSL::Cipher.new "aes-256-cbc"
    aes.decrypt
    aes.key = key
    aes.iv = iv
    aes.padding = 0
    aes.update(ciphertext) + aes.final
end

#
# main
#

open_vault "#{ENV["HOME"]}/Downloads/opvault.opvault", "password"
