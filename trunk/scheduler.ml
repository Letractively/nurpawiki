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

open Lwt
open ExtList
open ExtString

open Services
open Types

open Util

let clamp_date_to_today date =
  let today = Date.today () in
  let d = date_of_string date in
  begin
    match Date.compare today d with
      -1 -> d
    | 0 | 1 -> today
    | _ -> assert false
  end

let wiki_page_links sp todo_in_pages todo = 
  let id = todo.t_id in
  let c = "wiki_pri_"^Html_util.string_of_priority todo.t_priority in
  Html_util.todo_page_links sp todo_in_pages ~link_css_class:(Some c) id

let view_scheduler_page sp =

  let scheduler_page_internal sp ~credentials =
    let today = Date.today () in
    let prettify_activation_date d =
      let d = date_of_string d in
      (* Clamp & prettify activation date *)
      begin 
        match Date.compare today d with
          -1 -> Printer.DatePrinter.sprint "%a %b %d, %Y" d
        | 0 | 1 -> "today"
        | _ -> assert false
      end in
    
    let todo_table_html sp todos =
      let todo_in_pages =
        Database.todos_in_pages (List.map (fun (_,todo) -> todo.t_id) todos) in

      let prev_heading = ref "" in
      let todo_rows = 
        List.map
          (fun (heading,todo) ->
             let todo_id_s = string_of_int todo.t_id in
             let heading_row =
               if !prev_heading <> heading then
                 begin
                   prev_heading := heading;
                   [tr (td ~a:[a_class ["rm_table_heading"]] [pcdata heading]) []]
                 end
               else
                 [] in
             let pri_style = Html_util.priority_css_class todo.t_priority in
             let todo_row =
               tr
                 (td ~a:[a_class ["rm_edit"]]
                    (Html_util.todo_edit_img_link sp ET_scheduler todo.t_id))
                 [td [raw_checkbox ~name:("t-"^ todo_id_s) ~value:"0" ()];
                  td [Html_util.complete_task_img_link sp todo.t_id];
                  (td ~a:[a_class ["no_break"; pri_style]] 
                     [pcdata (prettify_activation_date todo.t_activation_date)]);
                  td ~a:[a_class [pri_style]] 
                    (Html_util.todo_descr_html 
                       todo.t_descr todo.t_owner @ wiki_page_links sp todo_in_pages todo)] in
             heading_row @ [todo_row]) todos in
      List.flatten todo_rows in

    let todo_section sp todos =
      (todo_table_html sp todos) in

    let query_todos = 
      if Privileges.can_schedule_all_tasks credentials then
        Database.query_upcoming_todos ~current_user_id:None
      else (* Query this users's tasks only: *)
        Database.query_upcoming_todos ~current_user_id:(Some credentials.user_id) in

    let upcoming_pending = query_todos (None,None) in
    let upcoming_tomorrow = query_todos (None,Some 1) in
    let upcoming_todos_7_days = query_todos (Some 1,Some 7) in
    let upcoming_todos_14_days = query_todos (Some 7, Some 14) in
    let upcoming_all = query_todos (Some 14, None) in

    let mark_todo_hdr h = List.map (fun e -> (h, e)) in
    let merged_todos = 
      (mark_todo_hdr "Today" upcoming_pending) @ 
        (mark_todo_hdr "Tomorrow" upcoming_tomorrow) @
        (mark_todo_hdr "Next 7 days" upcoming_todos_7_days) @
        (mark_todo_hdr "Next 2 weeks" upcoming_todos_14_days) @
        (mark_todo_hdr "Everything else" upcoming_all) in

    (* TODO merge this HTML generation with other pages.  PROBLEM:
       don't know how to easily do that without duplicating the
       parameter passing of pages. *)
    let table () = 
      [p [raw_input ~input_type:`Submit ~value:"Mass edit" ()];
       table
         (tr (th []) [th []; th []; th [pcdata "Activates on"]; th [pcdata "Todo"]])
         (todo_section sp merged_todos)] in

    let table' = 
      post_form edit_todo_page sp table (ET_scheduler, None) in
    
    Html_util.html_stub sp
      (Html_util.navbar_html sp ~credentials
         ([h1 [pcdata "Road ahead"]] @ [table'])) in
  Session.with_user_login sp
    (fun credentials sp -> 
       scheduler_page_internal sp credentials)
  

let render_edit_todo_cont_page sp ~credentials = function
    ET_scheduler -> 
      view_scheduler_page sp
  | ET_view wiki_page ->
      Nurpawiki.view_wiki_page sp ~credentials (wiki_page,None)

(* /scheduler *)
let _ =
  register scheduler_page
    (fun sp todo_id () ->
       view_scheduler_page sp)

let scheduler_page_discard_todo_id = 
  register_new_service
    ~path:["scheduler"] 
    ~get_params:((Eliomparameters.user_type 
                   et_cont_of_string string_of_et_cont "src_service"))
    (fun sp (src_page_cont) () -> 
       Session.with_user_login sp
         (fun credentials sp ->
            render_edit_todo_cont_page sp ~credentials src_page_cont))
         
(* Save page as a result of /edit_todo?todo_id=ID *)
let service_save_todo_item =
  register_new_post_service
    ~fallback:scheduler_page_discard_todo_id
    ~post_params:(list "todos"
                    ((int "todo_id") **
                       (string "activation_date") ** 
                       (string "descr") ** 
                       (int "owner_id")))
    (fun sp src_page_cont todos ->
     Session.with_user_login sp
       (fun credentials sp ->
          (* TODO security hole: would need to check user privileges
             for these DB operations. *)
          List.iter
            (fun (todo_id,(activation_date,(descr,owner_id))) ->
               Database.update_todo_descr todo_id descr;
               Database.update_todo_owner_id todo_id owner_id;
               Database.update_todo_activation_date todo_id activation_date)
            todos;
          render_edit_todo_cont_page sp ~credentials src_page_cont))

let rec render_todo_editor sp ~credentials (src_page_cont, todos_to_edit) =
  let users = Database.query_users () in
  let todos_str = String.concat "," (List.map string_of_int todos_to_edit) in
  let todos = Database.query_todos_by_ids todos_to_edit in
  
  let f =
    let todo_in_pages =
      Database.todos_in_pages (List.map (fun todo -> todo.t_id) todos) in

    let cancel_page cont = 
      match cont with
        ET_scheduler -> Html_util.cancel_link scheduler_page sp ()
      | ET_view wiki -> Html_util.cancel_link wiki_view_page sp (wiki,None) in

    let owner_selection chain todo =

      let match_owner u = function
          Some o -> o.owner_id = u.user_id
        | None -> false in
      
      let options = 
        List.map 
          (fun u -> 
             Option ([], u.user_id, Some (pcdata u.user_login),
                     match_owner u todo.t_owner))
          users in
      int_select ~name:chain (List.hd options) (List.tl options) in

    let todo_descr chain v =
      string_input ~input_type:`Text ~name:chain ~value:v () in

    (* See nurpawiki_calendar.js for JavaScript calendar binding
       details. *)
    let create_listform f = 
      [table 
         (tr (th [pcdata "ID"]) 
            [th [pcdata "Description"]; th [pcdata "Activates on"]])
         (f.it
            (fun (tv_id,(tv_act_date,(tv_descr,tv_owner_id))) todo ->
               let pri_style = 
                 Html_util.priority_css_class todo.t_priority in
               [tr ~a:[a_class [pri_style]]
                  (td [pcdata (string_of_int todo.t_id)])
                  [td (todo_descr tv_descr todo.t_descr :: 
                         wiki_page_links sp todo_in_pages todo);
                   td ~a:[a_class ["no_break"]] 
                     [string_input ~a:[a_id ("calendar_"^(string_of_int todo.t_id))]
                        ~input_type:`Text ~name:tv_act_date 
                        ~value:todo.t_activation_date ();
                      button ~a:[a_id ("button_"^(string_of_int todo.t_id)); 
                                 a_name "cal_trigger"] 
                        ~button_type:`Button [pcdata "..."]];
                   td [owner_selection tv_owner_id todo;
                       int_input ~name:tv_id ~input_type:`Hidden ~value:todo.t_id ()]]])
            todos
            [tr (td [string_input ~input_type:`Submit ~value:"Save" ();
                     cancel_page src_page_cont]) []])] in

    post_form ~service:service_save_todo_item ~sp create_listform src_page_cont in

  let heading = [pcdata ("Edit TODOs "^todos_str)] in
  let help_str = 
    pcdata "NOTE: Below activation date will be assigned for all the items" in

  let calendar_js = 
    [["jscalendar"; "calendar.js"];
     ["jscalendar"; "lang"; "calendar-en.js"];
     ["jscalendar"; "calendar-setup.js"];
     ["nurpawiki_calendar.js"]] in


  Html_util.html_stub sp ~javascript:calendar_js
    (Html_util.navbar_html sp ~credentials
       ((h1 heading)::[help_str; br(); f]))

let error_page sp msg =
  Html_util.html_stub sp [h1 [pcdata ("ERROR: "^msg)]]

let render_todo_get_page sp (src_page_cont, todo) = 
  match todo with
    Some todo_id ->
      render_todo_editor sp (src_page_cont, [todo_id])
  | None ->
      (* Bogus input as we didn't get any todos to edit..  But let's
         just take the user back to where he came from rather than
         issueing an error message. *)
      render_edit_todo_cont_page sp src_page_cont
        
let _ =
  register edit_todo_get_page
    (fun sp get_params () ->
       Session.with_user_login sp
         (fun credentials sp ->
            render_todo_get_page sp ~credentials get_params))

let todo_id_re = Pcre.regexp "^t-([0-9]+)$"

let parse_todo_ids todo_ids = 
  try
    List.map
      (fun (todo_id_str,b) ->
         match match_pcre_option todo_id_re todo_id_str with
           Some r ->
             int_of_string r.(1)
         | None ->
             raise Not_found) todo_ids
  with
    Not_found ->
      []
        

let _ =
  register edit_todo_page
    (fun sp (src_page_cont, single_tid) (todo_ids : (string * string) list) ->
       Session.with_user_login sp
         (fun credentials sp ->
            if todo_ids = [] then
              render_todo_get_page sp ~credentials 
                (src_page_cont, single_tid)
            else 
              render_todo_editor sp ~credentials
                (src_page_cont, (parse_todo_ids todo_ids))))

