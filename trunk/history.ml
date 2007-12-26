
module P = Printf
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

let descr_of_activity_type = function
    AT_create_todo -> "Created"
  | AT_complete_todo -> "Completed"
  | AT_work_on_todo -> "Worked on"
  | AT_create_page -> "Created"
  | AT_edit_page -> "Edited"
  | AT_uncomplete_todo -> "Resurrected"

module ReverseOrdString = 
  struct
    type t = String.t
    let compare a b = String.compare b a
  end

module RSMap = Map.Make (ReverseOrdString)

type act_group = 
    {
      ag_created_todos : (string * string * page list) list;
      ag_completed_todos : (string * string * page list) list;
      ag_resurrected_todos : (string * string * page list) list;
      ag_edited_pages : page list;
      ag_page_editors : string list;
    }

let empty_act_group = 
  {
      ag_created_todos = [];
      ag_completed_todos = [];
      ag_resurrected_todos = [];
      ag_page_editors = [];
      ag_edited_pages = [];
  }

let group_activities activities activity_in_pages =
  List.fold_left
    (fun acc a ->
        let date = date_of_date_time_string a.a_date in
        let d = Printer.DatePrinter.sprint "%Y-%m-%d" date in
        let ag = try RSMap.find d acc with Not_found -> empty_act_group in
        let pages = try IMap.find a.a_id activity_in_pages with Not_found -> [] in
        let opt_to_str o = Option.default "" o in
        let ag' = 
          let changed_by = opt_to_str a.a_changed_by in
          match a.a_activity with
            AT_create_todo ->
              (match a.a_todo_descr with
                 Some descr ->
                   let e = (descr, changed_by, pages)::ag.ag_created_todos in
                   { ag with ag_created_todos = e }
               | None -> P.eprintf "no descr in activity_log %i\n" a.a_id; ag)
          | AT_complete_todo ->
              (match a.a_todo_descr with
                 Some descr ->
                   let e = (descr, changed_by, pages)::ag.ag_completed_todos in
                   { ag with ag_completed_todos = e }
               | None -> P.eprintf "no descr in activity_log %i\n" a.a_id; ag)
          | AT_uncomplete_todo ->
              (match a.a_todo_descr with
                 Some descr ->
                   let e = (descr, changed_by, pages)::ag.ag_resurrected_todos in
                   { ag with ag_resurrected_todos = e }
               | None -> P.eprintf "no descr in activity_log %i\n" a.a_id; ag)
          | AT_create_page | AT_edit_page ->
              let add_editor e acc =
                if List.mem e acc then acc else e::acc in
              { ag with 
                  ag_page_editors = add_editor changed_by ag.ag_page_editors;
                  ag_edited_pages = pages @ ag.ag_edited_pages }
          | AT_work_on_todo -> ag in
        RSMap.add d ag' acc)
    RSMap.empty activities

let remove_duplicates strs = 
  let module PSet = 
    Set.Make (struct
                type t = page 
                let compare a b =  compare a.p_descr b.p_descr
              end) in
  let s = 
    List.fold_left (fun acc e -> PSet.add e acc) PSet.empty strs in
  PSet.fold (fun e acc -> e::acc) s []

let view_history_page sp ~cur_user =

  let activity = Database.query_past_activity () in
  let activity_in_pages = Database.query_activity_in_pages () in

  let prettify_date d =
    let d = date_of_date_time_string d in
    Printer.DatePrinter.sprint "%a %b %d, %Y" d in

  let activity_groups = group_activities activity activity_in_pages in

  let act_table = 
    table ~a:[a_class ["todo_table"]]
      (tr (th []) [th [pcdata "Activity"]; 
                   th [pcdata "By"];
                   th [pcdata "Details"]])
      (List.rev
         (fst 
            (RSMap.fold
               (fun date e (lst_acc,prev_date) ->
                  let prettified_date = prettify_date date in
                  let date_text =
                    if prev_date = prettified_date then
                      []
                    else 
                      [pcdata prettified_date] in

                  let todo_html ty lst = 
                    List.rev
                      (List.mapi
                         (fun ndx (todo,changed_by,pages) ->
                            (tr (td [])
                               [td (if ndx = 0 then [pcdata ty] else []);
                                td ~a:[a_class ["todo_owner"]] [pcdata changed_by];
                                td ([pcdata todo] @ 
                                      (Html_util.todo_page_links_of_pages 
                                         ~colorize:true sp pages))]))
                         lst) in

                  let created_todos = 
                    todo_html "Created" e.ag_created_todos in
                  let completed_todos = 
                    todo_html "Completed" e.ag_completed_todos in
                  let resurrected_todos = 
                    todo_html "Resurrected" e.ag_resurrected_todos in
                  let pages_html = 
                    if e.ag_edited_pages <> [] then
                      [tr (td [])
                         [td [pcdata "Edited"];
                          td 
                            ~a:[a_class ["todo_owner"]] 
                            [pcdata (String.concat "," e.ag_page_editors)];
                          td (Html_util.todo_page_links_of_pages sp 
                                ~colorize:true ~insert_parens:false 
                                (remove_duplicates e.ag_edited_pages))]]
                    else 
                      [] in
                  
                  (* NOTE: 'tr' comes last as we're building the page
                     in reverse order *)
                  (pages_html @ created_todos @ completed_todos @ resurrected_todos @
                     [tr (td ~a:[a_class ["no_break"; "h_date_heading"]] date_text) []] @ lst_acc,
                   prettified_date))
               activity_groups ([],"")))) in
  Html_util.html_stub sp
    (Html_util.navbar_html sp ~cur_user
       ([h1 [pcdata "Blast from the past"]] @ [act_table]))

(* /history *)
let _ =
  register history_page
    (fun sp todo_id () ->
       Session.with_user_login sp
         (fun cur_user sp ->
            view_history_page sp ~cur_user))
