$.get('clndr-template.html', function(data){
    $('.clndr').clndr({
        events: [
            {
                "date": Date.now(),
                "title": "Test",
            },
            {
                end: '2016-10-20',
                start: '2016-10-15',
                title: 'Another Long Event'
            },
        ],
        template: data,
        clickEvents: {
            click: function(target){
                console.log(target);
            },
        },
        forceSixRows: true,
        multiDayEvents: {
            endDate: 'end',
            singleDay: 'date',
            startDate: 'start'
        },

    });
});
