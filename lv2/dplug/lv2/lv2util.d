/*
  Copyright 2016 David Robillard <http://drobilla.net>
  Copyright 2018 Ethan Reker <http://cutthroughrecordings.com>

  Permission to use, copy, modify, and/or distribute this software for any
  purpose with or without fee is hereby granted, provided that the above
  copyright notice and this permission notice appear in all copies.

  THIS SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
*/
module dplug.lv2.lv2util;

import core.stdc.string;
import dplug.lv2.lv2;

/**
Return the data for a feature in a features array.

If the feature is not found, NULL is returned.  Note that this function is
only useful for features with data, and can not detect features that are
present but have NULL data.
*/
void* lv2_features_data(const (LV2_Feature*)* features, const char*        uri)
{
    if (features) {
        for (const (LV2_Feature*)* f = features; *f; ++f) {
            if (!strcmp(uri, (*f).URI)) {
                return cast(void*)(*f).data;
            }
        }
    }
    return null;
}
