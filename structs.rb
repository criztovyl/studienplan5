#!/usr/bin/env ruby
# Part of a utility to convert HTMLed-XLS Studienpläne into iCal.
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

require "./util"; include StudienplanUtil

Plan = Struct.new("Plan", :name, :clazz, :elements)

# This is the struct for storing event information
PlanElement = Struct.new("PlanElement", :title, :clazz, :room, :time, :dur, :lect, :nr, :special, :more) do

    def self.FullWeek(title, clazz, room, date, more=nil)
        #                                         dur  lect  nr
        return self.new(title, clazz, room, date, nil, nil, nil, :fullWeek, more)
    end

    def format(obj, format="%s", empty="", opts=[])
        if obj.class.name == Clazz.name
            if opts.include? :simple
                format % obj.simple
            else
                format % obj.to_s
            end
        elsif obj.class.name == DateTime.name
            if opts.include? :fullWeek
                format % formatWeek(obj)
            else
                format % formatTime(obj)
            end
        else
            StudienplanUtil.format_non_empty(obj, format, empty, opts)
        end
    end

    def to_s

        title = format(self.title, " %s")
        clazz = format(self.clazz, " for %s")
        more = format(self.more, " (%s)")

        case self.special
        when nil
            time = format(self.time)
            dur = format(self.dur, "@%s")
            nr = format(self.nr, "#%s")
            room = format(self.room, " at room %s")
            lect = format(self.lect, " by %s")
            return time + dur + title + nr + clazz + room + lect + more
        when :fullWeek
            time = format(self.time, "%s", "", [:fullWeek])
            return time + title + clazz + more + " (Full Week)"
        end
    end

    public
    def add_to_icalendar(icalendar)
        tzid=icalendar.timezones[0].tzid.to_s
        icalendar.event do |evt|

            title = format(self.title)
            clazz = format(self.clazz, "Klasse/Jahrgang: %s")
            more = format(self.more)

            nr = format(self.nr, "#%s")
            room = format(self.room)
            lect = format(self.lect, "Dozent: %s. ")

            dtend = self.time + 5 if self.special == :fullWeek


            evt.dtstart = Icalendar::Values::DateTime.new self.time, 'tzid' => tzid

            if dtend
                evt.dtend = Icalendar::Values::DateTime.new dtend, 'tzid' => tzid
            elsif self.dur
                evt.dtend = Icalendar::Values::DateTime.new self.time + self.dur/24.0, 'tzid' => tzid
            else
                evt.dtend = Icalendar::Values::DateTime.new self.time + 1.0/60/24, 'tzid' => tzid # Events must have end thats not equal to start, set dur 1 min
            end

            evt.summary = title + nr
            evt.location = room
            evt.description = "#{lect}#{more}#{clazz}" + ( ( dtend or self.dur ) ? "" : "\nNo end time defined, set duration to 1 minute." )

            #evt.uid = "de.joinout.criztovyl.studienplan5.planElement." + self.clazz.id_str + "." + title+nr # TODO: UID. This is not unique, find something.
        end
    end
end

# This is the Struct for storing class information
Clazz = Struct.new(:name, :course, :cert, :jahrgang, :group) do

    def self.Jahrgang(name)
        return self.new(nil, nil, nil, name)
    end

    def to_s

        jahrgang = format(self.jahrgang, "Jahrgang %s")
        full_name = format(self.full_name, ", %s")
        course = format(self.course,  ", Course %s")
        cert = format(self.cert, ", Cert. %s")

        jahrgang + full_name + course + cert
    end

    def full_name
        format(self.group, format(self.name, "%s-%%s"), format(self.name, "%s", nil))
        #self.group ? self.name.to_s + "-" + self.group.to_s : self.name.to_s
    end

    def full_jahrgang
        format(self.course, format(self.jahrgang, "%s(%%s)"), format(self.jahrgang))
        #self.course ? self.jahrgang.to_s + "(" + self.course.to_s + ")" : self.jahrgang
    end

    def simple
        self.name ? "%s(%s)" % [self.full_name, self.full_jahrgang] : "#{self.full_jahrgang}"
    end

    def format(str, format="%s", empty="", opts=[])
        StudienplanUtil.format_non_empty(str, format, empty, opts)
    end

    def parent
        # Jahrgang > Course > Cert > Name > Group
        ret = self.dup
        if self.group
            ret.group = nil
        elsif self.name
            ret.name = nil
        elsif self.cert
            ret.cert = nil
        elsif self.course
            ret.course = nil
        elsif self.jahrgang
            ret = nil
        end
        ret
    end
end
