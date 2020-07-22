/*
* Copyright (c) 2020 Louis Brauer (https://github.com/louis77)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: Louis Brauer <louis77@member.fsf.org>
*/

using Gee;

public errordomain SourceError {
    UNAVAILABLE
}

public delegate ArrayList<RadioBrowser.Station> Tuner.FetchType(uint offset, uint limit) throws SourceError;

public class Tuner.DirectoryController : Object {
    public RadioBrowser.Client provider { get; set; }
    public Model.StationStore store { get; set; }

    public signal void tags_updated (ArrayList<RadioBrowser.Tag> tags);

    public DirectoryController (RadioBrowser.Client provider, Model.StationStore store) {
        this.provider = provider;
        this.store = store;

        // migrate from <= 1.2.3 settings to json based store
        this.migrate_favourites ();
    }


    public StationSource load_random_stations (uint limit) {
        var params = RadioBrowser.SearchParams() {
            text  = "",
            tags  = new ArrayList<string>(),
            order = RadioBrowser.SortOrder.RANDOM
        };
        var source = new StationSource(limit, params, provider, store);
        return source;
    }

    public StationSource load_trending_stations (uint limit) {
        var params = RadioBrowser.SearchParams() {
            text    = "",
            tags    = new ArrayList<string>(),
            order   = RadioBrowser.SortOrder.CLICKTREND,
            reverse = true
        };
        var source = new StationSource(limit, params, provider, store);
        return source;
    }

    public StationSource load_popular_stations (uint limit) {
        var params = RadioBrowser.SearchParams() {
            text    = "",
            tags    = new ArrayList<string>(),
            order   = RadioBrowser.SortOrder.CLICKCOUNT,
            reverse = true
        };
        var source = new StationSource(limit, params, provider, store);
        return source;
    }

    public StationSource load_search_stations (owned string utext, uint limit) {
        var params = RadioBrowser.SearchParams() {
            text    = utext,
            tags    = new ArrayList<string>(),
            order   = RadioBrowser.SortOrder.CLICKCOUNT,
            reverse = true
        };
        var source = new StationSource(limit, params, provider, store); 
        return source;
    }

    public void migrate_favourites () {
        var settings = Application.instance.settings;
        var starred_stations = settings.get_strv ("starred-stations");
        if (starred_stations.length > 0) {
            warning ("Found settings-based favourites, migrating...");
            var params = RadioBrowser.SearchParams() {
                uuids = new ArrayList<string>.wrap (starred_stations)
            };
            var source = new StationSource(99999, params, provider, store); 
            try {
                foreach (var station in source.next ()) {
                    store.add (station);
                }  
                settings.set_strv ("starred-stations", null);  
                warning ("Migration completed, settings deleted");     
            } catch (SourceError e) {
                warning ("Error while trying to migrate favourites, aborting...");
            }
        }
    }

    public StationSource load_by_tags (owned ArrayList<string> utags) {
        var params = RadioBrowser.SearchParams() {
            text    = "",
            tags    = utags,
            order   = RadioBrowser.SortOrder.VOTES,
            reverse = true
        };
        var source = new StationSource(40, params, provider, store);
        return source;
    }

    public void star_station (Model.Station station) {
        station.starred = true;
        store.add (station);
    }

    public void unstar_station (Model.Station station) {
        station.starred = false;
        store.remove (station);
    }

    public void count_station_click (Model.Station station) {
        provider.track (station.id);
    }

    public void load_tags () {
        try {
            var tags = provider.get_tags ();
            tags_updated (tags);
        } catch (RadioBrowser.DataError e) {
            warning (@"unable to load tags: $(e.message)");
        }
    }

}

public class Tuner.StationSource : Object {
    private uint _offset = 0;
    private uint _page_size = 20;
    private bool _more = true;
    private RadioBrowser.SearchParams _params;
    private RadioBrowser.Client _client;
    private Model.StationStore _store;

    public StationSource (uint limit, 
                          RadioBrowser.SearchParams params, 
                          RadioBrowser.Client client,
                          Model.StationStore store) {
        Object ();
        // This disables paging for now
        _page_size = limit;
        _params = params;
        _client = client;
        _store = store;
    }

    public ArrayList<Model.Station>? next () throws SourceError {
        // Fetch one more to determine if source has more items than page size 
        try {
            var raw_stations = _client.search (_params, _page_size + 1, _offset);
            var stations = convert_stations (raw_stations);
            augment_with_userinfo (stations);
            _offset += _page_size;
            _more = stations.size > _page_size;
            if (_more) stations.remove_at( (int)_page_size);
            return stations;    
        } catch (RadioBrowser.DataError e) {
            throw new SourceError.UNAVAILABLE("Directory Error");
        }
    }

    public bool has_more () {
        return _more;
    }

    private ArrayList<Model.Station> convert_stations (ArrayList<RadioBrowser.Station> raw_stations) {
        var stations = new ArrayList<Model.Station> ();
        foreach (var station in raw_stations) {
            var s = new Model.Station (
                station.stationuuid,
                station.name,
                station.country,
                station.url_resolved);
            s.favicon_url = station.favicon;
            s.clickcount = station.clickcount;
            stations.add (s);
        }
        return stations;
}

    private void augment_with_userinfo (ArrayList<Model.Station> stations) {
        foreach (Model.Station station in stations) {
            if (_store.contains (station)) {
                station.starred = true;
            }
        }
    }
}