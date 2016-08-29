$('.clndr').clndr({
    events: [
    {
        "date": Date.now(),
        "title": "Test",
    },
    ],
    template: $("#clndr-tmpl").html(),
    clickEvents: {
        click: function(target){
            console.log(target);
        },
    },

});
