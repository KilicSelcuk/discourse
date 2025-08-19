#!/usr/bin/env ruby

input = ARGF.read

FileUtils.chdir("app/assets/javascripts/discourse")

input
  .scan(/Looking up '([^']+)' is no longer permitted. Rename to '([^']+)' instead/)
  .each do |match|
    old = match[0]
    new = match[1]

    old_path = old.sub(/(\w+):/, '\1s/')
    new_path = new.sub(/(\w+):/, '\1s/')

    FileUtils.mkdir_p(File.dirname(new_path))
    FileUtils.mv(old_path, new_path)

    puts "#{old_path} #{new_path}"
  end
