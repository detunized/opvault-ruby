#!/usr/bin/env ruby

# Copyright (C) 2018 Dmitry Yakimenko (detunized@gmail.com).
# Licensed under the terms of the MIT license. See LICENCE for details.

# TODO: Better incorrect password detection
# TODO: Better error reporting

require "base64"
require "json"
require "openssl"

class Account < Struct.new :id, :name, :username, :password, :url, :note, :folder
    def initialize id:, name:, username:, password:, url:, note:, folder:
        super id, name, username, password, url, note, folder
    end
end

class Folder < Struct.new :id, :name
    def initialize id:, name:
        super id, name
    end
end

class KeyMac < Struct.new :key, :mac_key
    def self.from_str s
        new s[0, 32], s[32, 32]
    end
end

# Used to mark items with no folder (not to use nil)
NO_FOLDER = Folder.new id: "-", name: "-"

def open_vault path, password
    # Load all the files
    profile = load_profile path
    encrypted_folders = load_folders path
    encrypted_items = load_items path

    # Derive key encryption key
    kek = derive_kek profile, password

    # Decrypt main keys
    master_key = decrypt_master_key profile, kek
    overview_key = decrypt_overview_key profile, kek

    # Decrypt, parse and convert folders
    folders = decrypt_folders encrypted_folders.values, overview_key

    # We're only interested in logins/accounts that are not deleted
    account_items = select_active_account_items encrypted_items.values

    # Check digital signatures on the accounts to see if the vault is not corrupted
    verify_item_tags account_items, overview_key

    # Decrypt, parse, convert and assign folders
    accounts = decrypt_items account_items, master_key, overview_key, folders

    # Done
    accounts
end

def verify_item_tags items, key
    items.each do |item|
        keys = (item.keys - ["hmac"]).sort
        values = keys.map { |k| item[k] }
        message = keys.zip(values).join

        stored = decode64 item["hmac"]
        computed = hmac_sha256 key.mac_key, message

        if computed != stored
            raise "Item tag doesn't match"
        end
    end
end

def select_active_account_items items
    items
        .select { |i| i["category"] == "001" } # 001 is a login item
        .reject { |i| i["trashed"] }
end

def decrypt_items items, master_key, overview_key, folders
    items.map { |i| decrypt_item i, master_key, overview_key, folders }
end

def decrypt_item item, master_key, overview_key, folders
    overview = decrypt_item_overview item, overview_key
    item_key = decrypt_item_key item, master_key
    details = decrypt_item_details item, item_key

    Account.new id: item["uuid"],
                name: overview["title"],
                username: find_detail_field(details, "username"),
                password: find_detail_field(details, "password"),
                url: overview["url"],
                note: details["notesPlain"],
                folder: folders[item["folder"]] || NO_FOLDER
end

def decrypt_item_overview item, overview_key
    JSON.load decrypt_base64_opdata item["o"], overview_key
end

def decrypt_item_key item, master_key
    raw = decode64 item["k"]

    if raw.size != 112
        raise "Item key is corrupted: invalid size"
    end

    iv = raw[0, 16]
    ciphertext = raw[16, 64]
    stored_tag = raw[80, 32]
    computed_tag = hmac_sha256 master_key.mac_key, iv + ciphertext

    if computed_tag != stored_tag
        raise "Item key is corrupted: tag doesn't match"
    end

    KeyMac.from_str decrypt_aes256 ciphertext, iv, master_key.key
end

def decrypt_item_details item, item_key
    JSON.load decrypt_base64_opdata item["d"], item_key
end

def find_detail_field details, name
    details.fetch("fields", [])
        .find_all { |i| i["designation"] == name }
        .map { |i| i["value"] }
        .first
end

def decrypt_folders folders, overview_key
    folders
        .reject { |i| i["trashed"] }
        .map { |i| decrypt_folder i, overview_key }
        .map { |i| [i.id, i] }
        .to_h
end

def decrypt_folder folder, overview_key
    overview = decrypt_folder_overview folder, overview_key

    Folder.new id: folder["uuid"],
               name: overview["title"]
end

def decrypt_folder_overview folder, overview_key
    JSON.load decrypt_base64_opdata folder["overview"], overview_key
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
    decrypt_base64_key profile["masterKey"], kek
end

def decrypt_overview_key profile, kek
    decrypt_base64_key profile["overviewKey"], kek
end

def decrypt_base64_key key_base64, kek
    raw = decrypt_base64_opdata key_base64, kek
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

accounts = open_vault "test.opvault", "password"
accounts.each_with_index do |i, index|
    puts "#{index + 1}: #{i.id}, #{i.name} #{i.username}, #{i.password}, #{i.url}, #{i.note}, #{i.folder.name}"
end
