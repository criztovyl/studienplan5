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
require "./structs"
require "./util"; include StudienplanUtil

# Hackedy hack hack
class Set

    def to_json(opts = nil)
        self.to_a.to_json(opts)
    end
end

class SemesterplanExtractor

    @@logger = $logger || Logger.new(STDERR)
    @@logger.level = $logger && $logger.level || Logger::INFO


    attr_reader :data

    def initialize(file)
        @file = file
        @data = Plan.new("Semsterplan")
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

        days_RE_text = "(#{days.join ?|})"

        # Default values for options
        default_dur = 3

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
            if td1.text == "Abkürzung"
                @@logger.debug "Plan End."
                planEnd = true
            elsif td1.text  =~ /\d{4}\/KW \d{1,2}/ # (year and cw) from above; YYYY/KW WW
                r = 0
                w += 1
            end unless td1.nil?

            if td0 and td0.text  =~ /^(\w{3}\d{4})$/ # (jahrgang) from above.
                @@logger.debug "Jahrgang #{$1.inspect}"
                unless jahrgangsColorKeys[w]; jahrgangsColorKeys[w] =  {}; end # One of the mentioned nested inits. Keep them in mind :)
                jahrgangsColorKeys[w].store(td0["bgcolor"], $1)
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

                    rowJahrgangClazz = Clazz::Jahrgang(rowJahrgang)

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

                        elementTexts = element.search("text()")

                        comment = nil
                        redo_queue = []

                        # Push the element type already, if present
                        if elementType
                            @@logger.debug "Type: #{elementType.inspect}"

                            @data.add_full_week(elementType, rowClass, nil, start)# nil = room

                        end

                        elementTexts.each do |textElement|

                            text = textElement.text.strip # Guess who used #to_s instead of #text and wondered why there where HTML entities everywhere.

                            #           Name                  Certificate
                            #           vvvvvvvvvvvv          vvvvv
                            if text =~ /(\w{2}\d{3})\+(\w+) \((\w+)\) (\w)/ # i.e. FS151+BSc (FST) d; (class), as mentioned above
                                #                     ^^^^^           ^^^^
                                #                     Course          Group

                                name = $1
                                course = $2  # Studiengang (BSc, BA)
                                cert = $3 # Zertifizierung (FST, FIS, ...)
                                group = $4

                                rowClass = Clazz.new(name, course, cert, rowJahrgang)

                                @data.extra[:classes].add rowClass

                                unless groups[rowJahrgang]; groups.store(rowJahrgang, {}); end
                                unless groups[rowJahrgang][group]; groups[rowJahrgang].store group, Set.new; end
                                groups[rowJahrgang][group].add rowClass

                                @@logger.debug "Class: #{rowClass}"

                                nil # return nothing to block
                            elsif date != "Gruppe" # Is the case when we're in first column

                                # This is RegEx for (element), as mentioned above
                                #
                                #        Weekdays* (or)           The word                          Room Nr/Name                 Lecturer Abbr.
                                #                                 "ab" (opt)                        (opt)                        (lazy) (opt)    <----+
                                #        vvvvvvvvvvvvvvvvvvv      vvvvvvvvv                         vvvvvvvvvvvv                 vvvvvvvvvvvvvvv      |
                                regex = /(#{days.join("|")})[\. ]?(?:ab ?)?((\d{1,2})(\.|:)(\d{2}))?(\[(.*?)\])? ?(.+(?:\(.*?\))?(?:-.{2,3}?\W)?)?/  #| One Group
                                #                                          ^^^^^^^^^^^^^^^^^^^^^^^^^               ^^^^^^^^^^^^^^                     |
                                #                                           time (digits separated                 Subject and group(s)   <-----------+
                                #                                           by ":" or ".") (opt)                   group(s) are opt
                                # * TODO: Replace with days_RE_text.


                                @@logger.debug "Text: #{text.inspect}" unless text.empty?

                                if text =~ /(.*):\n(.*)/m
                                    @@logger.debug "Comment. #{$2.inspect}"
                                    comment = $2
                                    next # Huh, it's not cool to jump out of the loop.
                                elsif text.include? "siehe Kommentar"

                                    @@logger.debug "Looking up comment."

                                    redo_queue = comment.split("\n")
                                    redo_queue.delete ""

                                    @@logger.debug "Comments: #{redo_queue.inspect}"

                                    textElement.content = redo_queue.pop
                                    redo # I like my redo queue.
                                end

                                scan = text.scan regex # These monstrous regex above.

                                @@logger.debug "Scan: #{scan}" unless scan.length == 0

                                # Determine wether is one of these ugly multi-days like this one: "Do/Fr/Sa WP-BI2(b/c)-Sam"
                                unless scan.length == text.split(" ")[0].scan(/(#{days_RE_text})/).length

                                        @@logger.info "Multiday! #{text.inspect}"

                                    multidays = []
                                    sep = nil
                                    lastDay = false

                                    text_ = text.gsub(/-\w{2,3}$/, "") # Lect. could be i.e. Sa.

                                    # I feel like I have to explain this algorithm.
                                    # - split by weekdays -> Using our example from above, that would be ["", "Do", "/", "Fr", "/", "Sa", " WP-BI2(b/c)-Sam"]
                                    # - iterate over the splitted string.
                                    #   + if its a weekday, store and set flag that it was.
                                    #   + if last was a day and separator is not set, yet, set it to the current part. Reset flag.
                                    #   + else reset flag only.
                                    # Somehow trivial?
                                    text_.split(/#{days_RE_text}/).each do |part|
                                        if part =~ /^#{days_RE_text}$/
                                            multidays.push part
                                            lastDay = true
                                        elsif lastDay and not sep
                                            sep=part
                                            lastDay = false
                                        else
                                            lastDay = false
                                        end
                                    end

                                    text.gsub! multidays.join(sep), "" # Using our ex. "Do/Fr/Sa" would get deleted from the string

                                    @@logger.debug "Result: #{text.inspect}, Sep: #{sep.inspect}, multidays: #{multidays}"

                                    multidays.each do |mday|
                                        redo_queue.push(mday + text) # Reassable the string for each day ("Do WP-BI2(b/c)-Sam", "Fr WP....", "Sa ....")
                                    end

                                    @@logger.debug "Redo..."

                                    textElement.content = redo_queue.pop
                                    redo # Did I already mentioned my NICE redo queue?
                                end unless text.empty?

                                # Now we dive into the more or less ugly code.
                                # (if-elsif-elsif)
                                # First, the best case: our RegEx matched.
                                if
                                    scan and
                                        ( match = scan[0] ) and # What if there is more than one match? Is that even possible?
                                        ( match.length == 8 ) and
                                        ( match[7] != nil ) #TODO: REFACTOR!

                                    day=match[0]
                                    hours=match[2]
                                    minutes=match[4]
                                    room=match[6]

                                    match7 = match[7].to_s.strip # match7 is shorter than match[7] xD

                                    @@logger.debug "Match"

                                    # pe -> plan element
                                    pe_start = start.dup
                                    pe_start += days.index day


                                    if hours and minutes
                                        pe_start += Rational(hours,24) + Rational(minutes,1440)  # 24h * 60min = 1440min
                                    end

                                    # Check what remaining information is there(if-else)

                                    # Subject, group/duration, lecturer, i.e. "DuA(1d)-Bö" or anything like "Subject(groups)-Lecturer"
                                    if match7 =~ /(.*)\((.*)\)(-(.*))?/ # RegEx: title, group or duration, lecturer with leading dash (optional), lecturer (sub-match from prev.)

                                        #TODO: Multi-Title. Like multi-days. Ugly things. I.e. "WIN2/KRC(4c1/c2)-Wi/Schw"

                                        title = $1
                                        group = $2
                                        lect = (lect = lects[$4]) ? lect : $4 # Translate abbr., if possible

                                        @@logger.debug "Lect: %s" % lect

                                        clazz = nil

                                        # Some group specials
                                        #
                                        # Refresher from group to title
                                        #TODO: From title to group as special nr. -1 maybe, thought it's illogial (Can't determine max. num. yet, would require another loop)
                                        refr="Refr"
                                        group.gsub! "Ref ", refr + " "
                                        if group.include? refr
                                            group.gsub! refr, ""
                                            group.strip!
                                            title += " " + refr
                                        end
                                        #
                                        # Group is class
                                        if group =~ /^(\w{2}\d{3})$/ # Class regex
                                            @@logger.debug "Class #{$1} in group"
                                            groups[rowJahrgang].each do |group_, classes|
                                                classes.each do |clazz_|
                                                    if clazz_.name == $1
                                                        clazz = clazz_
                                                    end
                                                end
                                            end
                                        end
                                        #
                                        # Preperation from group as nr. 0
                                        prep="vor1"
                                        if group.include? prep
                                            group.gsub! prep, "0"
                                        end
                                        if group =~ /(.+)-/
                                            wrong = $1
                                            @@logger.warn "Something in group that does not belog there: #{wrong.inspect}"
                                            group.gsub!(wrong + "-", "")
                                            title += " " + wrong
                                            @@logger.debug title
                                        end

                                        # Parse the groups. (if-else)
                                        #
                                        # Exams. Groups = duration. We can receive more info from comment.
                                        if title =~ /(KL-.*|.*-KL|WP .*|-WP .*)/i or group =~ /^\d+$/

                                            @@logger.debug "Klausur/Wahlpflicht #{title.inspect} #{group.inspect} (#{comment.inspect})" # #inspect to see non-printing chars (\r, \n)

                                            room = nil

                                            room_RE = / ?Raum (.*)/
                                            if ( comment =~ room_RE ) # Huh, are the parenthesis required?
                                                comment.gsub! room_RE, ""
                                                room = $1
                                            end

                                            @@logger.debug "Rest-Comment #{comment.inspect}, rowJahrgang #{rowJahrgang}, Room #{room.inspect}"

                                            dur_ = group.empty? ? nil : Rational(group, 60)

                                            # Multi Courses! dafuq.
                                            #TODO: We should put that (the ugly multi-* things) into a function.
                                            unless comment.nil?

                                                course_RE = /(b\.?sc\.?|b\.?a\.?)/im

                                                courses = []
                                                sep = nil
                                                last_was_course = false

                                                comment.split(course_RE).each do |split|
                                                    if split =~ course_RE
                                                        courses.push $1.gsub(".", "")
                                                        last_was_course = true
                                                    elsif last_was_course and not sep and split.length == 1
                                                        sep = split
                                                        last_was_course = false
                                                    else
                                                        last_was_course = false
                                                    end
                                                end

                                                @@logger.debug "Courses %s, sep %s" % [courses.inspect, sep.inspect]

                                                comment.gsub!(course_RE, "").strip!
                                                comment.gsub!(sep, "") if sep

                                                comment = nil if comment.empty?

                                                courses.each do |course_name|

                                                    clazz = rowJahrgangClazz.dup
                                                    clazz.course = course_name

                                                    @@logger.debug "Clazz: #{clazz}, Comment: #{comment.inspect}"

                                                    @data.push({title: title, class: clazz, room: room, time: pe_start, dur: dur_, more: comment})
                                                end
                                            end
                                        else # No exam, groups = groups

                                            @@logger.debug "Searching groups"

                                            # This is if we have a plain class in groups.
                                            if clazz
                                                @@logger.debug "Using defined class #{clazz}"

                                                @data.push({title: title, class: clazz, room: room, time: pe_start, dur: default_dur, lect: lect})
                                                next # Huh, these jumping again.
                                            end

                                            nr = nil

                                            group.scan(/(\w)(\d?)/).each do |grp|  # Group regex; 0 = group name, 1 = group part, i.e: c2: $0 = c, $1 = 2

                                                @@logger.debug "Group #{grp}"

                                                # Match can be event nr or a group (finally!)
                                                if grp[0] =~ /^\d+$/ and grp[1].empty?
                                                    nr = grp[0]
                                                else
                                                    # A group contain multiple classes, create element for both.
                                                    classes = groups[rowJahrgang][grp[0]]

                                                    if classes
                                                        classes.each do |groupclazz|

                                                            unless groupclazz.nil? or grp[1].nil? or grp[1].empty?
                                                                groupclazz = groupclazz.dup
                                                                groupclazz.group = grp[1]
                                                            end

                                                            # TODO Why there's a nil check but below we use groupclazz even if it's nil? Huh?
                                                            @@logger.debug "Class #{groupclazz.simple}, pe_start #{pe_start}"

                                                            @data.push({title: title, class: groupclazz, room: room, time: pe_start, dur: default_dur, lect: lect, nr: nr})
                                                            @data.extra[:classes].add(groupclazz)
                                                        end
                                                    else
                                                        @@logger.error "We don't know group %s yet! Please fix in XLS manually (row %s/col %s) and re-convert to HTML." % [grp[0].inspect, i, k]
                                                    end
                                                end
                                            end
                                        end
                                    else # We got some other info
                                        match7 = match[7].to_s.strip

                                        @@logger.debug "Match7 ALTERN"

                                        # Catch all the specialities we know. (There are exams without a duration! Who does this?)
                                        #
                                        #             Special titles $1                                                              Title $4 and room $5 only
                                        #             vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv                vvvvvvvvvvvvv
                                        if match7 =~ /(Testat-.*|Refr .*|Info (?:zu )?.*|.*-WP .*|.*KL.*|.*-Tutorium)|(.*)-(\w{2,3})|(.*) ?\[(.*)\]/
                                            #                                                                         ^^^^^^^^^^^^^^
                                            #                                                                         Something $2 with
                                            #                                                                         a lecturer $3

                                            @data.push({title: $1||$2||$4, class: rowClass||rowJahrgangClazz, room: $5, time: pe_start, lect: (lect = lects[$3]) ? lect : $3})

                                        else # Currently have no example for this in mind, sry. But it's not special. That's good, isn't it? (Found one: "Präs-WP BI2")
                                            @data.push({title: match7, class: rowClass||rowJahrgangClazz, time: pe_start})
                                        end

                                        @@logger.info "#{match7} with title #{match7}, class #{rowClass||rowJahrgangClazz}, time #{pe_start}."
                                    end # We're done with the information.

                                    # The redo queue I mentioned.
                                    if redo_queue.length > 0
                                        @@logger.debug "Next element in redo queue"
                                        textElement.content = redo_queue.pop
                                        redo
                                    end
                                elsif text =~ /(.*?) ?\[(.*)\]/ # Our general-purpose RegEx did not match. Try a RegEx for elems like "Studienpräsenz [24]". These are full-week events.
                                    @@logger.debug "Title #{$1.inspect} and Room #{$2.inspect} only. Comment #{comment.inspect}"

                                    # If we have another full-week-event, replace it.
                                    @data.elements.delete_if do |e|
                                        e[:title] == elementType and e[:time] == start
                                    end

                                    @data.add_full_week($1, rowClass, $2, start, comment)

                                elsif not text.empty? # That's the worst case. Warn and simply add.
                                    @@logger.warn "Fall-trough! #{text.inspect}"
                                    @data.add_full_week(text, rowClass||rowJahrgangClazz, nil, start)

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
