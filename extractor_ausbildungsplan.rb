require "json"
require "./structs.rb"
require "Date"

class ExtractorAusbildungsplan

	attr_reader :data

	def initialize(file)
		@file = file
		@data = nil
	end

	def extract()
		klasse = Clazz.new("FS151","BSc","FST","ABB2015")
		planElemente=[]
		inhalt = JSON.parse(@file.readlines.join(?\n))
		inhalt.shift
		woche=""
		zeitraum=""
		freieTage=""
		taetigkeit=""
		for zeile in 0..4
			for spalte in 0..10
				zx4=zeile*4;
				woche = inhalt[zx4][spalte]["text"]
				zeitraum = inhalt[zx4+1][spalte]["text"]
				freieTage = inhalt[zx4+2][spalte]["text"]
				if(inhalt[zx4+3][spalte]["text"] != "")
					taetigkeit = inhalt[zx4+3][spalte]["text"]
				end
				next if woche.empty?
				#puts woche
				#puts zeitraum
				#puts freieTage
				#puts taetigkeit
				#puts ""
				#puts ""
				planElemente.push(Struct::PlanElement::FullWeek(taetigkeit,klasse,nil,DateTime.strptime("1 "+woche+" 20"+zeitraum[-2,2],"%u KW %W %Y"),freieTage))
			end
		end
		@data={klasse => planElemente}
	end

end