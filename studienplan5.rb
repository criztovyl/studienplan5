#!/usr/bin/env ruby
# A utility to convert HTMLed-XLS Studienpläne into iCal.
# Copyright (C) 2016 Christoph criztovyl Schulz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

##########
# README #
##########
#
# Some advices before you read my code.
#
#  -- Nothing so far --
##########

require "nokogiri"
require "date"
require "logger"
require "set"
require "icalendar"
require "icalendar/tzinfo"
require "json/add/struct"
require "optparse"
require "fileutils"
require "tzinfo"
require "./util"; include StudienplanUtil
require "./structs"
require "./extractor_semesterplan"

# Default values for options
ical_dir = "ical"
data_file = "data.json"
classes_file = "classes.json"

$logger = Logger.new(STDERR)
$logger.level= Logger::DEBUG

# Command line opts
$options = {}

OptionParser.new do |opts|
    opts.banner = "Usage: %s [options] [FILE]" % $0
    opts.separator ""
    opts.separator "FILE is a HTMLed XLS Studienplan."
    opts.separator "FILE is optional to be able to do -w/--web without reparsing everything."
    opts.separator ""

    opts.on("-c", "--calendar", "Generate iCalendar files to \"ical\" directory. (Change with --calendar-dir)") do |c|
        $options[:ical] = c
    end

    opts.on("-j", "--json", "Generate JSON data file (data.json).") do |j|
        $options[:json] = j
    end

    opts.on("-d", "--classes", "Generate JSON classes structure (classes.json).") do |j|
        $options[:classes] = j
    end

    opts.on("-o", "--output NAME", "Specify output target, if ends with slash, will be output directory. If not, will be name of calendar dir and prefix for JSON files.") do |o|
        $options[:output] = o
    end

    opts.on("-k", "--disable-json-object-keys", "Stringify keys that are not strings.") do |jok|
        $options[:no_jok] = jok
    end

    opts.on("-p", "--json-pretty", "Write pretty JSON data.") do |jp|
        $options[:json_pretty] = jp
    end

    opts.on("-w", "--web", "Export simple web-page for browsing generated icals. Does nothing unless -o/--output is a directory.") do |web|
        $options[:web] = web
    end

    opts.on("-n", "--calendar-dir NAME", "Name for the diretory containing the iCal files. Program exits status 5 if -o/--output is specified and not a directory.") do |cal_dir|
        $options[:cal_dir] = cal_dir
    end

    opts.on("-u", "--disable-unified", "Do not create files that contain all parent events recursively.") do |u|
        $options[:no_unified] = u
    end

    opts.on("-a", "--disable-apache-config", "Do not export .htaccess and other Apache-specific customizations.") do |no_apache|
        $options[:no_apache] = no_apache
    end

    opts.on("-s", "--simulate", "Simulate, do not write files or create directories.") do |simulate|
        $options[:simulate] = simulate
    end

    opts.on("-q", "--quiet", "Do not print data.") do |quiet|
        $options[:quiet] = quiet
    end

    opts.on("-l", "--level [LEVEL]", {fatal: Logger::FATAL, error: Logger::ERROR, warn: Logger::WARN, info: Logger::INFO, debug: Logger::DEBUG}, "Log level") do |level|
        $logger.level = level
    end

    opts.on("-h", "--help", "Print this help.") do |h|
        puts opts
        exit
    end

end.parse!

if $options[:cal_dir]
    ical_dir = $options[:cal_dir]
end

outp = $options[:output]
if outp
    if outp.end_with?(?/)
        ical_dir = outp + ical_dir
        data_file = outp + data_file
        classes_file = outp + classes_file

        Dir.mkdir(outp) unless Dir.exists?(outp) or $options[:simulate]
    else
        ical_dir = outp
        data_file = outp + ".data.json"
        classes_file = outp + ".classes.json"

        if $options[:cal_dir]
            $logger.error "Specified calendar dir name but output is not specified as directory"
            exit 5
        end
    end
end

if file = ARGV[0]
    se = SemesterplanExtractor.new(file)
    data = se.extract
end

# JSON data file version
$data_version = "1.01"

if data

    if $options[:json]
        json_data = {
            json_object_keys: $options[:no_jok] ? false : true,
            json_data_version: $data_version,
            generated: Time.now,
            data: $options[:no_jok] ? data : StudienplanUtil.json_object_keys(data)
        }

        $logger.debug "Writing JSON data file \"%s\"" % data_file

        if $options[:simulate]
            $logger.info "Would write #{data_file}"
        else
            File.open(data_file, "w+") do |datafile|
                datafile.puts $options[:json_pretty] ? JSON.pretty_generate(json_data) : JSON.generate(json_data)
            end
        end

        $logger.info "Wrote JSON data file \"%s\"" % data_file
    end

    if $options[:ical]
        tz=TZInfo::Timezone.get "Europe/Berlin"
        cal_stub = Icalendar::Calendar.new
        no_unified = $options[:no_unified] ? :only_self : nil

        cal_stub.prodid = "-Christoph criztovyl Schulz//studienplan5 using icalendar-ruby//DE"
        cal_stub.add_timezone tz.ical_timezone(Time.now)

        Dir.mkdir(ical_dir) unless Dir.exists?(ical_dir) or $options[:simulate]

        $logger.info "Writing unified calendars." unless no_unified

        data.each_key do |clazz|

            $logger.debug "Class: #{clazz}"

            cal = cal_stub.dup
            clazz_file = ical_dir + File::SEPARATOR + StudienplanUtil.class_ical_name(clazz) + ".ical"

            clazz_file.gsub!(/\.ical/, ".unified.ical") unless no_unified
            data.add_to_icalendar clazz, cal, no_unified

            $logger.debug "Writing calendar file \"%s\"" % clazz_file

            if $options[:simulate]
                $logger.info "Would write #{clazz_file}"
            else
                File.open(clazz_file, "w+") do |f|
                    f.puts cal.to_ical
                end
            end
        end

        $logger.info "Wrote calendar files to \"%s\"" % ical_dir
    end

    if $options[:classes]
        json_data = {
            json_object_keys: $options[:no_jok] ? false : true,
            json_data_version: $data_version,
            generated: Time.now,
            ical_dir: $options[:cal_dir],
            unified: $options[:no_unified] ? false : true,
            data: {}
        }
        export = json_data[:data]
        data.keys.each do |key|
            if key.full_name
                export.store(key, [])
                parent = key
                while parent = parent.parent
                    export[key].push parent if data.keys.include? parent
                end
            end
        end
        json_data[:data] = StudienplanUtil.json_object_keys(export) unless $options[:no_jok]

        $logger.debug "Writing JSON classes file \"%s\"" % classes_file

        if $options[:simulate]
            $logger.info "Would write #{classes_file}"
        else
            File.open(classes_file, "w+") do |datafile|
                datafile.puts $options[:json_pretty] ? JSON.pretty_generate(json_data) : JSON.generate(json_data)
            end
        end

        $logger.info "Wrote JSON classes file \"%s\"" % classes_file
    end
end

if $options[:web] and $options[:output] and $options[:output].end_with?(?/)

    $logger.info "Copying web content to %s" % $options[:output]

    sep = File::SEPARATOR
    o = $options[:output] + sep

    if $options[:simulate]
        $logger.info "Would copy ./web/ to #{o}"
    else
        FileUtils.cp_r "web/.", o
        if not $options[:no_apache]
            if Dir.exists? ical_dir
                FileUtils.mv o + "indexes_header.html", ical_dir
                FileUtils.cp o + "cover.css", ical_dir + sep + "indexes_css.css"
            else
                $logger.info "Target dir for icals does not exist, please specify it's name by --calendar-dir to enable custom Apache indexes style."
            end
        else
            FileUtils.rm [o + ".htaccess", o + "indexes_header.html"]
        end
    end

    $logger.warn "You haven't exported classes (-d/--classes) yet but they are required by -w/--web!" unless File.exists?(o+"classes.json")
    $logger.debug "Copied."
end
