select * from {{ ref('rpt_water_followup') }} where follow_up_status = 'closed'
