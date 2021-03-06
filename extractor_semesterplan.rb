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
# Variable names are mixed German and English: I take words (like jahrgang) from German but plural will be Englisch (jahrgangs) instead of German (jahrgänge).
#   Will describe the German words below this.
# Why?
#  The words because there is no English equivalant for some words or it would be much too long for a variable name,
#  the plural to make it easier for you to determine if a variable is a single element or a list, without knowing the German plural. (as above: jahrgangs instead of jahrgänge)
#
# Words:
#  - Jahrgang is a group of classes entered school/training/studies at same year
#
# Some variables still named CamelCase, will replace them by underscore_names little by little.
#
# - nil-checks mostly like "result = myBeNil.method if myBeNil". The same applies for empty-checks.
# - "init. nested array/hash/whatever" mostly looks like "unless container[mayBeElement]; container[mayBeElement] = []; end"
# - sometimes I do short-hand if-not-nil-then-else like element = ( element = element.mayBeNil ) ? /* Not nil */ : element /* because element is nil :D */
# - yeah, this codes handles HTML and uses RegEx. But not to parse the HTML. Don't parse HTML with RegEx!
##########

require "nokogiri"
require "date"
require "logger"
require "set"
require_relative "structs"
require_relative "util"; include StudienplanUtil
require_relative "cellparser"

# Hackedy hack hack
class Set

    def to_json(opts = nil)
        self.to_a.to_json(opts)
    end
end

class SemesterplanExtractor

    @@logger = $logger || Logger.new(STDERR)
    @@logger.level = $logger && $logger.level || Logger::INFO

    @@kw_re = /\d{4}\/KW \d{1,2}/ # year and cw, e.g. 2016/KW 23
    @@jahrgang_re = /^(\w{3}\d{4})$/ # a jahrgang, e.g. ABB2016
    @@class_cell_re = /^\w{2}(\d{2})\d{1}\+\w+ \(\w+\) \w$/ # a class cell, e.g. FS151+BSc (FST) d. Groups: YY, group)


    attr_reader :data

    def initialize(file)
        @file = file
        @data = Plan.new("Semsterplan")
        @parser = CellParser.new
    end

    def extract

        # Array for the plan.
        # Struc: Nested arrays.
        # Level 1 indices are the plan rows
        # Level 2 indices are the plan row parts
        # Level 3 indices are the plan row part elements
        plan = []

        # Array for the legend.
        # Struc: Nested arrays.
        # Level 1 indices are legend columns
        # Level 2 indices are legend column elements
        legend = []

        # Hash-Array for colors of row headings for jahrgangs.
        # Struc.: Hashes in Array
        # Indices are row parts, keys are colors, values are the jahrgangs (last two are Strings)
        jahrgangsColorKeys = []

        # Hash for cell bg-color -> cell type (SPE/ATIW/pratical placement)
        # Keys are colors, values are types. Both Strings.
        cellBGColorKeys = {}

        # Set for all classes
        @data.extra[:classes] = Set.new

        # Hash for abbreviated to full lecturers
        # Keys are abbr., values are full lecturers. Both Strings.
        lects={}

        # Hash jahrgang -> group -> class.
        # Struc.: Hash -> Hash -> Set (Set in Hash in Hash)
        # Level 1 keys are jahrgangs, level 2 keys groups and elements are classes. Group is a String, both remaining are a Clazzes.
        # Example: { jahrgang1: { group1: [class1, class2], group2: [class2] }, jahrgang2: {group1: [class3], group2: [class4] } }
        groups = {}

        # Flags and counters :)
        r=0 # Row
        w=-1 # Table wrap
        planEnd=false # plan to legend parsing

        # Need this to determine offset when calculating start date. (German abbreviations for weekdays; maybe could solve this by locale, but what if user hasn't installed that?)
        days=["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

        # Default values for options
        default_dur = 3.25

        # Hackedy hack hack
        def groups.to_s # For debugging :)
            str = "{ "
            self.each do |jahrgang, groups|
                str += jahrgang + ": { "
                groups.each do |group, classes|
                    str += group + ": ["
                    classes.each do |clazz|
                        str += "<#{clazz.to_s}> , "
                    end
                    str = str[0..str.length-3] # Remove last ", "
                    str += "], "
                end
                str = str[0..str.length-3]
                str += "}, "
            end
            str = str[0..str.length-3]
            str
        end

        # Step one, parse file into nested arrays and parse data we need before (esp. background colors)
        #
        # Doc. struc.:
        # Row 0 is Part 0 is Element 0
        # Row 1 is Part 0 is Element 1
        # Row 2 is Part 0 is Element 2
        # Row 3 is Part 1 is Element 0
        # Row 4 is Part 1 is Element 1
        # Row 5 is Part 1 is Element 2
        # ...
        #
        #
        # There are five kinds of rows:
        #  1. (empty) (year and cw) (year and cw) ... : later this will be "cw"; (year and cw) looks like "2016/KW 10"
        #  2. "Gruppe" (date) (date) (date) ...       : later this will be "date"; (date) looks like "07.03-12.03"
        #  3. (class) (element) (element) ...         : (class) looks like "FS151+BSc (FST) d", for (element) see "regex" (way) below.
        #  4. (empty) (element) (element) ...
        #  5. (jahrgang) (element) (element) ...      : jahrgang looks like "ABB2015"
        #
        # Normal occurrence: (1.) (2.) (some 3.) (some 4. with one 5. somewhere). Last one will loop some times. (some times, not sometimes)

        @@logger.info "Step one"

        doc = Nokogiri::HTML @file

        doc.xpath("//tr").each do |tr|

            tds = tr.xpath("td")

            # tdN is shorter than tds[N] :D
            td0 = tds[0]
            td1 = tds[1]

            key = (key = td0) ? key.text : key

            # Legend starts with this.
            # TODO: Why Worst-case first?!
            if td1.text == "Abkürzung"
                @@logger.debug "Plan End."
                planEnd = true
            elsif td1.text  =~ @@kw_re # (year and cw) from above; YYYY/KW WW
                r = 0
                w += 1
            end unless td1.nil?

            if td0 and td0.text =~ @@class_cell_re # (class) from above
                jg = "ABB20#{$1}"
                @@logger.debug "Jahrgang #{jg.inspect} (Class: #{td0.text.inspect})"
                unless jahrgangsColorKeys[w]; jahrgangsColorKeys[w] =  {}; end # One of the mentioned nested inits. Keep them in mind :)
                jahrgangsColorKeys[w].store(td0["bgcolor"], jg)
            end

            if not planEnd
                unless plan[r]; plan.push []; end
                plan[r].push tds
            else
                # Legend is column-orientated
                tr.xpath("td").map.with_index do |td, index|
                    if index >= legend.length; legend.push []; end # Huh, not very secure xD
                    legend[index].push td
                end
            end

            r += 1 # No superfluous comment here :*
        end

        @@logger.debug "jahrgangsColorKeys #{jahrgangsColorKeys.inspect}"

        @@logger.debug { "legend #{legend.map { |e| e[0].text }}" }

        # Step two: Parse stored data
        #

        # Cell BG color assoc., legend 7 is the color key, 8 the name.
        # Only cells 12..14
        # TODO: Somehow detertime non-hard-coded or use command line arg. (Currently preferring arg., but requires user interaction, preferring automatic execution)
        # @TODO Forget it. It's static, it's okay the way it is.

        for n in 12..14
            cellBGColorKeys.store(legend[7][n]["bgcolor"], legend[8][n].text)
        end

        @@logger.debug "cellBGColorKeys #{cellBGColorKeys.inspect}"

        # Lecturers in legend 4 and 5
        l_i=4
        legend[l_i].each.with_index do |lect,index|
            next if lect.text == "Dozentenkürzel" or lect.text.empty?

            lects.store lect.text, legend[l_i+1][index].text
        end

        @@logger.debug "Lecturers #{lects.inspect}"

        @@logger.info "Finished step one: %s parts, max %s elements." % [w+1,r+1]
        @@logger.info "Step two."

        # Remeber the struct? It's row -> row part -> element
        # TODO: Replace .map with .each
        plan.map.with_index do |row, i|

            # First two rows are headings only (1. and 2. from above)
            if i > 1

                row.each.with_index do |rowPart, j|

                    # Use the BG color we already got in step 1
                    rowJahrgang = ( rowHeader = rowPart[0]) ? rowHeader["bgcolor"] : ""
                    rowJahrgang = ( colorKey = jahrgangsColorKeys[j] ) ? colorKey[rowJahrgang] : ""

                    next unless rowJahrgang

                    rowJahrgangClazz = Clazz.new().with_year(rowJahrgang[-4,4].to_i) # 2015 of "ABB2015"

                    rowClass = nil

                    # to_a because the type has no #each that supports #with_index, its a Nokogiri::XML::NodeSet
                    rowPart.to_a.each.with_index do |element, k|

                        @@logger.debug "row #{i}, part #{j}, element #{k}"

                        # As mentioned above step 1
                        cw = ( cw = plan[0][j][k] ) ? cw.text : cw
                        date = (date = plan[1][j][k] ) ? date.text : date

                        if date == "Gruppe"
                            start = nil
                        else
                            #                                   "2016" of "2016/KW 9"
                            #                                            vvvvvvvv
                            start = DateTime.strptime("1" + date[0..5] + cw[0..3], "%u%d.%m-%Y") # %u is day of week
                            #                               ^^^^^^^^^^
                            #                         "29.02-" of "29.02-05.03"
                        end

                        # Type SPE/ATIW/...
                        elementType = ( elementType = element["bgcolor"] ) ? cellBGColorKeys[elementType] : elementType

                        elementTexts = element.search("font > text()")
                        comment = element.search("comment")

                        @@logger.debug("elementtexts: #{elementTexts.inspect}, comments: #{comment.inspect}")
                        @@logger.debug("elementtexts: #{elementTexts.length}, comments: #{comment.length}")

                        # Push the element type already, if present
                        if elementType
                            @@logger.debug "Type: #{elementType.inspect}"

                            # TODO: Describe better: This is set because first loop never enters here before rowClass is set.
                            @data.add_full_week(elementType, rowClass, nil, start) # nil = room

                        end

                        elementTexts.each do |textElement|

                            text = textElement.text.strip # Guess who used #to_s instead of #text and wondered why there where HTML entities everywhere.
                            comment = comment ? comment.text.strip : ""


                            @@logger.debug "Text: #{text}"

                            if text =~ @@class_cell_re # (class), as mentioned above

                                rowClass = Clazz::from_full_name(text)

                                @data.extra[:classes].add rowClass

                                unless groups[rowJahrgang]; groups.store(rowJahrgang, {}); end
                                unless groups[rowJahrgang][rowClass.group]; groups[rowJahrgang].store rowClass.group, Set.new; end
                                groups[rowJahrgang][rowClass.group].add rowClass

                                @@logger.debug "Class: #{rowClass}"

                                nil # return nothing to block
                            elsif date != "Gruppe" # Is the case when we're in first column

                                @@logger.debug "Text   : #{text}"
                                @@logger.debug "Comment: #{comment.inspect}"

                                @parser.parse(text)

                                res = @parser.result

                                @@logger.debug { "Orig  : #{text.inspect}"}
                                @@logger.debug {
                                    "Parsed: " + ("%s%s[%s] %s(%s)-%s" % [
                                        res[:day].join(?/), res[:time].join(?/), res[:rooms].join(?/),
                                        res[:subj].join(?\ ), res[:groups].join(?/), res[:lect].join(?/)]).strip.inspect
                                }

                                @@logger.debug { @parser.result.inspect }

                                res[:lect].map! {|lect| lects[lect] || lect }

                                element = { title: res[:subj].join(?\ ).strip, dur: res[:dur] || default_dur, time: nil, nr: nil, room: res[:rooms].join(?/), lect: res[:lect].join(?/), more: nil, class: nil }

                                if res[:day].empty?
                                    res[:day].push "Mo"
                                    element[:special] = :fullWeek
                                end

                                res[:day].each.with_index do |day,di|

                                    @@logger.debug { day }

                                    pe_start = start.dup
                                    pe_start += days.index day

                                    if res[:time].length > 0
                                       time = res[:time][res[:time].length >= di ? di : 0]
                                       if /(?<hours>\d{1,2}):(?<minutes>\d{2})/ =~ time
                                           pe_start += Rational(hours,24) + Rational(minutes,1440)  # 24h * 60min = 1440min
                                       end
                                    end

                                    element[:time] = pe_start

                                    # This should be last, add anything else before
                                    #
                                    if res[:groups].empty?

                                        @@logger.debug { "Groups empty ..." }

                                        pushed = false

                                        if comment =~ /B\.?Sc\.?/

                                            @@logger.debug { "B.Sc. exam" }

                                            element[:class] = (rowClass || rowJahrgangClazz).with_course("BSc")
                                            @data.push element.dup

                                            pushed = true
                                        end

                                        if comment =~ /B\.?A\.?/

                                            @@logger.debug { "B.A. exam" }

                                            element[:class] = (rowClass || rowJahrgangClazz).with_course("BA")
                                            @data.push element.dup

                                            pushed = true
                                        end

                                        unless pushed
                                            @@logger.debug { rowClass ? "rowClass" : "rowJahrgangClazz" }
                                            element[:class] = rowClass || rowJahrgangClazz
                                            @data.push element.dup
                                        end

                                    else
                                        res[:groups].each do |group|

                                            @@logger.debug "Searching groups"

                                            if group =~ /^(?<num>\d)?(?<key>\w)(?<part>\d)?$/

                                                @@logger.debug "Group #{group}, key #{$~[:key]}"

                                                # A group contain multiple classes, create element for both.
                                                classes = groups[rowJahrgang][$~[:key]]

                                                if classes
                                                    classes.each do |groupclazz|

                                                        unless $~[:part].nil?
                                                            groupclazz = groupclazz.with_part $~[:part]
                                                        end

                                                        element[:class] = groupclazz

                                                        @@logger.debug "Class #{groupclazz.simple}, pe_start #{pe_start}"
                                                        @@logger.debug { "Adding element #{element.inspect}" }

                                                        @data.push element.dup
                                                        @data.extra[:classes].add(groupclazz)
                                                    end

                                                    next

                                                else
                                                    @@logger.error "We don't know group %s yet! Please fix in XLS manually (row %s/col %s) and re-convert to HTML." % [$~.string.inspect, i, k]
                                                end
                                            else
                                                @@logger.warn "Something in group that does not belong there! Appending \"(#{group})\" to title."
                                                element[:title] += " (#{group})"
                                                element[:class] = rowJahrgangClazz
                                                @data.push element.dup
                                            end
                                        end
                                    end
                                end
                            end # ignore "Gruppe" texts
                        end if elementTexts # element texts iteration
                    end # elements iteration
                end # parts iteration
            end # skip first two rows
        end # rows iteration
        @data # return from method
    end
end
