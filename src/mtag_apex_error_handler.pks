create or replace package mtag_apex_error_handler
as

  function handle_error
  (
    p_error in apex_error.t_error
  )
    return apex_error.t_error_result
  ;

end mtag_apex_error_handler;
/
