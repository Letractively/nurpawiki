(* Copyright (c) 2006, 2007 Janne Hellsten <jjhellst@gmail.com> *)

(* 
 * This program is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation, either version 2 of the
 * License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.  You should have received
 * a copy of the GNU General Public License along with this program.
 * If not, see <http://www.gnu.org/licenses/>. 
 *)

open XHTML.M
open Eliomsessions
open Eliomparameters
open Eliomservices
open Eliompredefmod.Xhtml

open Types

open Lwt

let wiki_view_page = 
  new_service ["view"] ((string "p")
                        ** (opt (bool "printable"))
                        ** (opt (int "r"))
                        ** (opt (bool "force_login"))) ()

let wiki_edit_page = new_service ["edit"] (string "p") ()

let scheduler_page = new_service ["scheduler"] unit ()

let edit_todo_get_page = new_service ["edit_todo"] 
  ((Eliomparameters.user_type 
      et_cont_of_string string_of_et_cont "src_service") **
     (opt (int "tid"))) ()

let edit_todo_page = 
  new_post_service
    ~fallback:edit_todo_get_page 
    ~post_params:any ()

let history_page = new_service ["history"] unit ()

let search_page = new_service ["search"] (string "q") ()

let benchmark_page = new_service ["benchmark"] (string "test") ()

let user_admin_page = new_service ["user_admin"] unit ()

let edit_user_page = new_service ["edit_user"] 
  (opt (string "caller") ** (string "user_to_edit")) ()

let disconnect_page = new_service ["disconnect"] unit ()

let about_page = new_service ["about"] unit ()

let page_revisions_page = new_service ["page_revisions"] (string "p") ()

let task_side_effect_complete_action =
  Eliomservices.new_coservice' ~get_params:(Eliomparameters.int "task_id") ()

let task_side_effect_undo_complete_action =
  Eliomservices.new_coservice' ~get_params:(Eliomparameters.int "task_id") ()

let task_side_effect_mod_priority_action = 
  Eliomservices.new_coservice' ~get_params:((Eliomparameters.int "task_id") **
                                              Eliomparameters.bool "dir") ()

