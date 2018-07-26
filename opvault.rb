#!/usr/bin/env ruby

require "json"

def open_vault path
    profile = parse_profile File.join(path, "default/profile.js")
end

def parse_profile filename
    content = File.read filename

    fail "Unsupported format" if !content.start_with? "var profile={"
    fail "Unsupported format" if !content.end_with? "};"

    JSON.load content[12..-2]
end

open_vault "#{ENV["HOME"]}/Downloads/opvault.opvault"
