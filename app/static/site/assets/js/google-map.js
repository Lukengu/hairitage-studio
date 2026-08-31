
function initHairitageMap() {
    var config = window.HAIRITAGE_MAP || {};
    var lat = config.lat || -26.1366667;
    var lng = config.lng || 28.1511111;
    var title = config.title || 'Hairitage Studio';
    var mapElement = document.getElementById('map');

    if (!mapElement || typeof google === 'undefined') {
        return;
    }

    var center = new google.maps.LatLng(lat, lng);
    var map = new google.maps.Map(mapElement, {
        zoom: 15,
        center: center,
        scrollwheel: false,
        styles: [
            {
                featureType: 'administrative.country',
                elementType: 'geometry',
                stylers: [{ visibility: 'simplified' }, { hue: '#ff0000' }],
            },
        ],
    });

    new google.maps.Marker({
        position: center,
        map: map,
        icon: '/static/site/assets/images/map_pin_9356230.png',
        title: title,
    });
}

window.initHairitageMap = initHairitageMap;
