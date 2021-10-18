create or replace package body mtag_apex_error_handler
as

  gc_default_message  varchar2(500 char) := 'Something did not work. Reference for further investigation: %0';
  gc_default_language varchar2(10 char)  := 'en';
  gc_schema_as_prefix boolean            := true;
  gc_add_prefix       varchar2(10 char)  := 'MTAG.';
  gc_default_name     varchar2(255 char) := gc_add_prefix || 'GENERAL_ERROR';
  gc_fatal_name       varchar2(255 char) := gc_add_prefix || 'FATAL_ERROR';

  procedure create_message
  (
    pi_application_id in number
  , pi_name           in varchar2
  , pi_language       in varchar2 default gc_default_language
  , pi_message_text   in varchar2 default gc_default_message
  )
  as
    pragma autonomous_transaction;
  begin
    apex_lang.create_message
    (
      p_application_id => pi_application_id
    , p_name           => pi_name
    , p_language       => pi_language
    , p_message_text   => pi_message_text
    );
    commit;
  end create_message;

  function extract_column_identifier
  (
    pi_ora_sqlerrm in varchar2
  )
    return varchar2
  as
    l_col_identifier   varchar2(32767);
    l_identifier_parts apex_t_varchar2;
    l_return           varchar2(32767);
  begin

    l_col_identifier := regexp_replace( pi_ora_sqlerrm, '.*\("(.*)"\."(.*)"\."(.*)"\).*', '\1.\2.\3', 1, 0, 'n' );

    if gc_schema_as_prefix then
      l_return := gc_add_prefix || l_col_identifier;
    else
      l_identifier_parts := apex_string.split( l_col_identifier, '.' );
      l_return := gc_add_prefix || l_identifier_parts(2) ||  '.' || l_identifier_parts(3);
    end if;

    return l_return;
  end extract_column_identifier;

  function get_message_name
  (
    pi_error in apex_error.t_error
  )
    return varchar2
  as
    l_message_name varchar2(255 char);
  begin

    -- ora-01400 cannot insert NULL (no constraint name)
    if pi_error.ora_sqlcode in (-1400, -1407) then
      l_message_name :=
        extract_column_identifier( pi_ora_sqlerrm => pi_error.ora_sqlerrm ) ||
        '.ORA' || to_char(pi_error.ora_sqlcode, 'FM000000')
      ;

    -- ora-00001 unique constraint violated
    -- ora-02290 check constraint violated
    -- ora-02091 transaction rolled
    -- ora-02291 parent not found
    -- ora-02292 children exist
    elsif pi_error.ora_sqlcode in (-1, -2091, -2290, -2291, -2292) then
      l_message_name :=
        gc_add_prefix ||
        apex_error.extract_constraint_name( p_error => pi_error , p_include_schema  => gc_schema_as_prefix ) || 
        '.ORA' || to_char( pi_error.ora_sqlcode, 'FM000000')
      ;
    else
      l_message_name := gc_default_name;
    end if;

    return l_message_name;
  end get_message_name;

  function handle_error
  (
    p_error in apex_error.t_error
  )
    return apex_error.t_error_result
  as
    l_reference_id varchar2(100 char);
    l_error_result apex_error.t_error_result;
    l_message_name varchar2(255 char);
  begin
    l_error_result := apex_error.init_error_result ( p_error => p_error );
    l_reference_id := sys_guid();

    if p_error.is_internal_error then
      if not p_error.is_common_runtime_error then
        l_error_result.message :=
          apex_lang.message
          ( 
            p_name           => gc_fatal_name
          , p0               => l_reference_id
          , p_application_id => nv('APP_ID')
          )
        ;
        l_error_result.additional_info := null;
      end if;
    -- apex validation errors can have no ora_sqlcode
    -- should use their message
    elsif p_error.ora_sqlcode is null then
      null;
    else
      l_error_result.display_location :=
        case
          when l_error_result.display_location = apex_error.c_on_error_page then apex_error.c_inline_in_notification
          else l_error_result.display_location
        end;

      l_message_name := get_message_name( pi_error => p_error );

      if l_message_name is not null then
        l_error_result.message :=
          apex_lang.message
          ( 
            p_name           => l_message_name
          , p_application_id => nv('APP_ID')
          , p0               => l_reference_id -- always add reference# to message
          );
        if l_error_result.message = l_message_name then
          create_message( pi_application_id => nv('APP_ID'), pi_name => l_message_name );
          l_error_result.message :=
            apex_lang.message
            ( 
              p_name           => l_message_name
            , p0               => l_reference_id
            , p_application_id => nv('APP_ID') 
            );
        end if;
      else
        if p_error.ora_sqlcode is not null then
          l_error_result.message := apex_error.get_first_ora_error_text ( p_error => p_error );            
        end if;
      end if;
      if l_error_result.page_item_name is null and l_error_result.column_alias is null then
        apex_error.auto_set_associated_item
        (
          p_error        => p_error
        , p_error_result => l_error_result 
        );
      end if;
    end if;    

    return l_error_result;
  end handle_error;

end mtag_apex_error_handler;
/
