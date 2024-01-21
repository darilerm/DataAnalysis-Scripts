with
/*
   ed -> event_dttm
   ldom -> last day of month
*/
monthly_events_calendar as (
  select last_day(event_dttm) as ed_ldom
    from table.user_events
  group by ed_ldom
  ),
first_monthly_user_events as (
  select user_id, last_day(min(event_dttm)) as ed_first_ldom
    from table.user_events
    where nvl(trim(user_id), '') != ''  -- There might be a few interactions with a NULLed or empty user_ids, please ignore those.
  group by user_id
),
all_monthly_user_events as (
  select c.ed_ldom, f.user_id
    from monthly_events_calendar             c
      left join first_monthly_user_events f
        on c.ed_ldom >= f.ed_first_ldom
),
unique_dates_in_ct as (
   select user_id, event_dttm::date as ed_dt
     from table.user_events
    where nvl(trim(user_id), '') != ''
    group by user_id, ed_dt
), 
count_of_monthly_user_events as (
   select last_day(ed_dt) as ed_ldom,
          user_id,
          count(1) as count_of_events
     from unique_dates_in_ct
    group by ed_ldom, user_id
),
standard_user_cohorts as (
   select ed_ldom, user_id,
          case
             when count_of_events > 7 then 'power_user'
             when count_of_events > 3 then 'frequent'
             else 'infrequent'
          end as sc
      from count_of_monthly_user_events
),
user_cohort_transitions as (
-- Standard cohorts [`infrequent`, `frequent` & `power_user`]
   select c.user_id,
          to_char(c.ed_ldom, 'yyyy-mm') as current_month,
          c.sc                          as current_cohort_value,
          p.sc                          as previous_cohort_value
      from standard_user_cohorts             c
        inner join standard_user_cohorts     p
          on c.user_id = p.user_id
          and c.ed_ldom = add_months(p.ed_ldom, -1)
    where current_cohort_value != previous_cohort_value  -- Excluding transitions that stayed within the same group
   union all
-- Special cohort `zombie` (applicable only on this_month)
   select a.user_id,
          to_char(a.ed_ldom, 'yyyy-mm') as current_month,
          'zombie'                      as current_cohort_value,
          p.sc                          as previous_cohort_value
    from all_monthly_user_events        a
      inner join standard_user_cohorts  p  /* I. `zombie` -> users had an event in the month before */
          on a.user_id = p.user_id
          and a.ed_ldom = add_months(p.ed_ldom, -1)
      left join standard_user_cohorts   c
        on a.user_id = c.user_id
        and a.ed_ldom = c.ed_ldom
   where c.user_id is null               /* II. `zombie` -> but no more event in the current one */
   union all
-- Special cohort `new` (applicable only on last_month)
   select s.user_id,
          to_char(s.ed_ldom, 'yyyy-mm') as current_month,
          s.sc                          as current_cohort_value,
          'new'                         as previous_cohort_value
    from standard_user_cohorts               s
      inner join first_monthly_user_events   f  /* `new` -> users had their first event in the current month */
        on s.user_id = f.user_id
        and add_months(s.ed_ldom, -1) = f.ed_first_ldom
    union all
-- Special cohort `reacquired` (applicable only on last_month)
   select s.user_id,
          to_char(s.ed_ldom, 'yyyy-mm') as current_month,
          s.sc                          as current_cohort_value,
          'reacquired'                  as previous_cohort_value
     from standard_user_cohorts                s
        inner join standard_user_cohorts       p  /* II. `reacquired` -> but were reacquired this month */
                on s.user_id = p.user_id
                and add_months(s.ed_ldom, -1) = p.ed_ldom
        inner join first_monthly_user_events   f  /* I.  `reacquired` -> users had their first event in a previous month */
                on p.user_id = f.user_id
                and add_months(p.ed_ldom, -1) = f.ed_first_ldom
),
cohort_transitions as (
   select current_month         as this_month,
          previous_cohort_value as last_month_status,
          current_cohort_value  as this_month_status,
          count(1)              as transitions
     from user_cohort_transitions
    group by this_month, last_month_status, this_month_status
)

select this_month, last_month_status, this_month_status, transitions
  from cohort_transitions
 order by this_month, this_month_status, last_month_status
;


-- Test
-- 1. Finding the min/max of the `yyyy-mm`
select min(last_day(event_dttm)) as min_ed_ldom,
       max(last_day(event_dttm)) as max_ed_ldom
  from table.user_events
; -- 2020-01 & 2023-05
