/*
 * (C) 2016 Christoph "criztovyl" Schulz
 * GPLv3 and later.
 * Part of studienplan5, a util to convert HTMLed-XLS Studienplände into iCal files.
 * https://github.com/criztovyl/studienplan5
 */
var classes, ical_dir, unified;

function Clazz(name, course, cert, jahrgang, group){
    this.name = name;
    this.course = course;
    this.cert = cert;
    this.jahrgang = jahrgang;
    this.group = group;
}

Clazz.Jahrgang = function(name){
    return new Clazz(undefined, undefined, undefined, name);
}

Clazz.from_json = function(json){
    if(json["json_class"] == "Clazz"){
        var v = json["v"];
        return new Clazz(v[0], v[1], v[2], v[3], v[4])
    }
    else {
        console.warn(json["json_class"] + " is not a Clazz!");
        console.log("-");
        console.debug(json);
        return false;
    }
}

Clazz.prototype = {
    simple: function(no_jahrgang_for_class){
        if(this.full_name() != undefined){
            var str = this.full_name();
            if(no_jahrgang_for_class == undefined)
                str += "(" + this.full_jahrgang() + ")";
            return str;
        }
        else if (this.jahrgang != undefined){
            return this.full_jahrgang();
        }
        else{
            return "";
        }
    },
    full_name: function(){
        if(this.name != undefined){
            if(this.group != undefined){
                return this.name + "-" + this.group;
            }
            else{
                return this.name;
            }
        }
        else{
            return undefined;
        }
    },
    full_jahrgang: function(){
        if(this.jahrgang != undefined){
            if(this.course != undefined){
                return this.jahrgang + "(" + this.course + ")";
            }
            else{
                return this.jahrgang;
            }
        }
        else {
            return undefined;
        }
    },
    ical_file_name: function(){
        var name = this.jahrgang;
        if (this.full_name() != undefined)
            name += "-" + this.full_name();
        if(this.course != undefined)
            name += "-" + this.course;
        if(this.cert != undefined)
            name += "-" + this.cert;

        if(unified)
            name += ".unified";

        return name + ".ical";
    },
    ical_file_link: function(into){

        var loc, webcal_url, ical_link, links, container;

        loc = location.href.split("/"); loc.pop();
        webcal_url = loc.join("/").replace(/https?:\/\//, "webcal://");

        ical_link = sprintf("%s/%s", ical_dir, this.ical_file_name());

        links = $("<span>");

        container = $("<p>").html(this.simple(false) + ": <br/>").appendTo(links);

        $("<label>").html("URL: ").appendTo(container);
        $("<input>").attr({"type": "text", "value": window.location.origin + window.location.pathname + ical_link, "disabled": "true"}).appendTo(container);
        $(container).append("<br>");
        $("<a>").attr({"href": ical_link, "target": "_blank"}).html(".ics herunterladen").appendTo(container);
        $(container).append("<br>");
        $("<a>").attr({"href": sprintf("%s/%s/%s", webcal_url, ical_dir, this.ical_file_name()), "target": "_blank"}).html("webcal öffnen (Outlook)").appendTo(container);

        $(container).appendTo(links);

        if(into != undefined){
            $(links).appendTo(into);
            return into;
        }
        else
            return links;
    }
}

function loadClasses(default_ical_dir){
    $.ajax("classes.json").done(function(data){
        console.log("Loaded classes");
        classes = [[],[]]; // 0 - keys, 1 - values

        var keyys, values;

        var json_data_version = data.json_data_version.split("."); // 0 - major, 1 - minor

        if (json_data_version[0] == "1"){

            if(Number(json_data_version[1]) >= 1){
                ical_dir = data.ical_dir;
                unified = data.unified;
                default_ical_dir && console.info("Called loadClasses with a parameter but classes.json is new enough.");
            }
            else {
                ical_dir = default_ical_dir || "ical";
                unified = false;
            }

            if(data.json_object_keys){
                keyys = data["data"][0];
                values = data["data"][1];

                $(document).ready(function(){
                    var select = $(".inner.cover#usage select")[0];
                    $(select).html("");
                    $("<option>").html("Bitte auswählen...").attr("value", -1).appendTo(select);

                    $.each(keyys, function(index, element){

                        var key = Clazz.from_json(element);
                        classes[0].push(key);
                        $("<option>").html(key.full_name()).attr("value", index).appendTo(select);

                        var values_new = [];

                        $.each(values[index], function(index, element){ // Attention, attention, ein Tann'bäumchen, ein Tann'bäumchen! values[index] => numeric key not index.
                            values_new.push(Clazz.from_json(element));
                        });

                        classes[1].push(values_new);


                    });

                    $(select).removeAttr("disabled");
                    $(select).on("change", classSelect);

                    if(getHashSelection() && select && select[0]){
                        $(select)[0].selectedIndex = Number(getHashSelection());
                        console.log("loadClasses / Hash Selection:");
                        console.log(getHashSelection());
                        $(select).change();
                    }
                });
            }
            else {
                console.error("Stringified keys are not supportet yet.");
            }
        }
        else {
            console.error("Unknown/Unspported JSON data version: " + json_data_version.join("."));
        }

    });
}

$(document).ready(function(){

    $(".nojs").hide();
    $(".inner.cover").hide();
    $(".inner.cover#home").show();
    $(".nav li#curr-home").addClass("active");

    $(window).on("hashchange", hashChange);

    hashChange();

    // protected email script by Joe Maller
    // modified by Christoph Schulz, 2016 (For the super paranoid)
    // // JavaScripts available at http://www.joemaller.com
    // // this script is free to use and distribute
    // // but please credit me and/or link to my site
    //
    var cloaked = 'join' + 'out' + '.com';
    cloaked = cloaked.replace(".com", ".de");
    cloaked = ('ch' + '.schulz' + '@' + cloaked);
    $("#contact #mail a").attr("href", "mailto:" + cloaked).html(cloaked);

});

var noHashChange = 0;
function hashChange(evt){

    if(noHashChange == 0){

        console.log("Hash change!");

        var target = window.location.hash; // Location hash incl. #. Keep it.
        if(String(target)){
            $(".inner.cover").hide();

            var selection_match = target.match(/-selection-(\d+)$/);
            if(selection_match) target = target.replace(selection_match[0], "");

            $(".inner.cover"  + target).show();
            $(".nav li.active").removeClass("active");
            $(".nav li#curr-" + target.replace("#", "")).addClass("active");

            if(selection_match){
                var select = $(".inner.cover#usage select");
                if(select && select[0] && !select[0].disabled){
                    console.log("hashChange / getHashSelection:");
                    console.log(getHashSelection());
                    $(select)[0].selectedIndex = Number(getHashSelection());
                    $(select).change();
                }
            }
        }
    }
    else {
        console.log("noHashChange +" + (noHashChange-1));
        noHashChange--;
    }
}

var hashSelectionRE = /-selection-(\d+)$/;

function getHashSelection(){
    var match = document.location.hash.match(hashSelectionRE);
    return match ? match[1] : match // It's undefined? Return undefined.
}

function setHashSelection(selectedIndex){
    noHashChange = 2;
    removeHashSelection();
    location.hash = location.hash + "-selection-" + selectedIndex;
}

function removeHashSelection(){
    location.hash = location.hash.replace(hashSelectionRE, "");
}
function classSelect(){

    var target = $($(".inner.cover#usage #icals ul#cal-links"))
    target.html("");

    if(String(this.value) && this.value != -1){

        classes[0][this.value].ical_file_link($("<li>")).appendTo(target);

        if(!unified){
            $.each(classes[1][this.value], function(index, element){
                element.ical_file_link($("<li>")).appendTo(target);
            });
        }

        $(".inner.cover#usage #icals").show();
        setHashSelection(this.selectedIndex);
    }
    else{
        $(".inner.cover#usage #icals").hide();
        console.log("select.value -1");
    }
}
