/*
 * Copyright (C) 2020 kmwallio
 * 
 * Modified August 29, 2020
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

using ThiefMD;
using ThiefMD.Widgets;

namespace ThiefMD.Controllers.SheetManager {
    private SheetPair _currentSheet;
    private Sheets _current_sheets;
    private Gee.Queue<SheetPair> _editors;
    private Gee.LinkedList<SheetPair> _active_editors;
    private Gtk.ScrolledWindow _view;
    private Gtk.InfoBar _bar;
    private Widgets.Editor _welcome_screen;

    public void init () {
        if (_editors == null) {
            _editors = new Gee.LinkedList<SheetPair> ();
        }

        if (_active_editors == null) {
            _active_editors = new Gee.LinkedList<SheetPair> ();
        }

        if (_view == null) {
            _view = new Gtk.ScrolledWindow (null, null);
            _bar = new Gtk.InfoBar ();
            _bar.revealed = false;
            _bar.show_close_button = true;
        }
    }

    public Gtk.ScrolledWindow get_view () {
        update_view ();

        return _view;
    }

    public void show_error (string error_message) {
        _bar.set_message_type (Gtk.MessageType.ERROR);
        var content = _bar.get_content_area ();
        var error_label = new Gtk.Label ("<b>" + error_message + "</b>");
        error_label.use_markup = true;
        content.add (error_label);
        _bar.show ();
        _view.show_all ();

        _bar.close.connect (() => {
            content.remove (error_label);
        });
    }

    private void update_view () {
        // Clear the view
        if (_welcome_screen != null) {
            _view.remove (_welcome_screen);
            _welcome_screen = null;
        }

        // Load the view
        if (_active_editors.size == 0) {
            _welcome_screen = new Widgets.Editor ("");
            _welcome_screen.hexpand = true;
            _view.add (_welcome_screen);
        } else {
            foreach (var editor in _active_editors) {
                editor.editor.hexpand = true;
                _view.add (editor.editor);
            }
        }

        _view.show_all ();
    }

    public string get_markdown () {
        StringBuilder builder = new StringBuilder ();
        for (int i = 0; i < _active_editors.size; i++) {
            SheetPair sp = _active_editors.get (i);
            string text = (sp == _currentSheet) ? sp.editor.preview_markdown : sp.editor.buffer.text;
            if (i > 0) {
                builder.append (FileManager.get_yamlless_markdown (text, 0, true, true, false));
            } else {
                builder.append (text);
            }
        }
        return builder.str;
    }

    public double get_cursor_position () {
        return 0.1;
    }

    public void set_sheets (Sheets sheets) {
        _current_sheets = sheets;
        UI.set_sheets (sheets);
    }

    public Sheets get_sheets () {
        return _current_sheets;
    }

    public static void refresh_sheet () {
        foreach (var editor in _active_editors) {
            editor.sheet.redraw ();
        }
    }

    public static Sheet get_sheet () {
        return _currentSheet.sheet;
    }

    public static bool load_sheet (Sheet sheet) {
        if (_currentSheet != null && sheet == _currentSheet.sheet && _active_editors.size == 1) {
            return true;
        }

        var settings = AppSettings.get_default ();
        Widgets.Editor loaded_file = null;

        if (sheet == null) {
            return false;
        }

        drain_and_save_active ();

        _currentSheet = null;
        foreach (var editor in _editors) {
            if (editor.sheet == sheet) {
                _currentSheet = editor;
            }
        }

        if (_currentSheet == null) {
            _currentSheet = new SheetPair ();
            _currentSheet.sheet = sheet;
            _currentSheet.editor = FileManager.open_file (sheet.file_path());
        } else {
            _editors.remove (_currentSheet);
        }

        _currentSheet.sheet.active = true;
        _currentSheet.editor.am_active = true;
        _active_editors.add (_currentSheet);
        loaded_file = _currentSheet.editor;

        debug ("Tried to load %s (%s)\n", sheet.file_path (), (loaded_file != null) ? "success" : "failed");

        update_view ();
        return loaded_file != null;
    }

    public static void new_sheet (string file_name) {
        string parent_dir = "";
        Sheets sheet = null;

        if (_current_sheets == null) {
            // Save the current file
            save_active ();

            // Attempt to create the sheet and switch to it
            if (_currentSheet != null) {
                sheet = _currentSheet.sheet.get_parent_sheets ();
                parent_dir = sheet.get_sheets_path ();
            }
        } else {
            sheet = _current_sheets;
            parent_dir = sheet.get_sheets_path ();
        }

        // Create the file and refresh
        if (parent_dir != "" && sheet != null) {
            if (FileManager.create_sheet(sheet.get_sheets_path (), file_name)) {
                sheet.load_sheets ();
            }
        } else {
            warning ("Could not create file, no current sheet");
        }
    }

    // Just finds headers and makes the bold...
    public string mini_mark (string contents) {
        string result = contents;
        try {
            Regex headers = new Regex ("^(#+)\\s(.+)", RegexCompileFlags.MULTILINE | RegexCompileFlags.CASELESS, 0);
            result = result.replace ("&", "&amp;");
            result = result.replace ("<", "&lt;").replace (">", "&gt;");
            result = headers.replace (result, -1, 0, "<b>\\1 \\2</b>");
        } catch (Error e) {
            warning ("Error: %s", e.message);
        }
        return result;
    }

    private static void drain_and_save_active () {
        foreach (var editor in _active_editors) {
            try {
                _view.remove (editor.editor);
                editor.sheet.active = false;
                editor.editor.am_active = false;
                editor.editor.save ();
                editor.sheet.redraw ();
            } catch (Error e) {
                warning ("Could not save file %s: %s", editor.sheet.file_path (), e.message);
            }
        }

        _active_editors.drain (_editors);
        check_queue ();
    }

    private static void save_active () {
        foreach (var editor in _active_editors) {
            try {
                editor.editor.save ();
                editor.sheet.redraw ();
            } catch (Error e) {
                warning ("Could not save file %s: %s", editor.sheet.file_path (), e.message);
            }
        }
    }

    private static void refresh_scheme () {
        var settings = AppSettings.get_default ();
        var scheme_id = settings.get_valid_theme_id ();
        foreach (var editor in _active_editors) {
            try {
                editor.editor.set_scheme (scheme_id);
            } catch (Error e) {
                warning ("Could not save file %s: %s", editor.sheet.file_path (), e.message);
            }
        }
    }

    public static bool close_active_file (string file_path) {
        SheetPair remove_this = null;
        foreach (var editor in _active_editors) {
            if (editor.sheet.file_path () == file_path) {
                remove_this = editor;
                try {
                    editor.editor.save ();
                    editor.sheet.redraw ();
                } catch (Error e) {
                    warning ("Could not save file %s: %s", editor.sheet.file_path (), e.message);
                }
            }
        }

        if (remove_this != null) {
            remove_this.editor.am_active = false;
            remove_this.sheet.active = false;
            _active_editors.remove (remove_this);
            _editors.remove (remove_this);
            _view.remove (remove_this.editor);
            remove_this.editor = null;
            remove_this.sheet = null;
            clear_view ();
        }

        return false;
    }

    private void clear_view () {
        foreach (var editor in _active_editors) {
            _view.remove (editor.editor);
        }
        update_view ();
    }

    public void last_modified (Widgets.Editor modified_editor) {
        if (_currentSheet != null && _currentSheet.editor == modified_editor) {
            return;
        }

        foreach (var editor in _active_editors) {
            if (editor.editor == modified_editor) {
                _currentSheet = editor;
            }
        }
    }

    public void check_queue () {
        while (_editors.size > Constants.KEEP_X_SHEETS_IN_MEMORY) {
            SheetPair clean = _editors.poll ();
            clean.editor.am_active = false;
            clean.editor = null;
            clean.sheet.active = false;
            clean.sheet = null;
            clean = null;
        }
    }

    public void redo () {
        if (_currentSheet != null) {
            _currentSheet.editor.redo ();
        }
    }

    public void undo () {
        if (_currentSheet != null) {
            _currentSheet.editor.undo ();
        }
    }

    private class SheetPair {
        public Sheet sheet;
        public Widgets.Editor editor;
    }
}
