IMPORT os
IMPORT FGL lib
&include "schema.inc"
DEFINE m_tabs DYNAMIC ARRAY OF STRING
MAIN
	DEFINE l_db STRING
	DEFINE i    SMALLINT = 0
	DEFINE c    base.Channel

	LET l_db = base.Application.getArgument(1)
	IF l_db.getLength() < 1 THEN
		LET l_db = fgl_getenv("DBNAME")
		IF l_db.getLength() < 1 THEN
			LET l_db = "training.db"
		END IF
	END IF

	IF NOT os.Path.exists(l_db) THEN
		CALL lib.log(1, SFMT("Create DB %1", l_db))
		LET c = base.Channel.create()
		CALL c.openFile(l_db, "a+")
		CALL c.close()
	END IF

	LET lib.m_debug_lev = 1
	CALL lib.log(0, "mk_db started ...")
	CALL lib.db_connect()

	LET m_tabs[i := i + 1] = "users"
	LET m_tabs[i := i + 1] = "emp01"
	LET m_tabs[i := i + 1] = "bra01"
	LET m_tabs[i := i + 1] = "device_login"
	LET m_tabs[i := i + 1] = "job01"
	LET m_tabs[i := i + 1] = "trim1"
	LET m_tabs[i := i + 1] = "trim2"
	LET m_tabs[i := i + 1] = "lists"
	LET m_tabs[i := i + 1] = "lista"
	LET m_tabs[i := i + 1] = "vehicle"
	LET m_tabs[i := i + 1] = "next_job"
	LET m_tabs[i := i + 1] = "lista_trim"
	LET m_tabs[i := i + 1] = "job_dates"
	LET m_tabs[i := i + 1] = "parts"

	CALL dropTables()
	CALL createTables()
	CALL insertTestData()

	CALL lib.exit_program(0, "Program Finished")
END MAIN
--------------------------------------------------------------------------------------------------------------
FUNCTION dropTables()
	DEFINE x      SMALLINT
	DEFINE l_stmt STRING
	FOR x = 1 TO m_tabs.getLength()
		LET l_stmt = "DROP TABLE " || m_tabs[x]
		CALL lib.log(1, l_stmt)
		TRY
			EXECUTE IMMEDIATE l_stmt
		CATCH
			DISPLAY SQLERRMESSAGE
		END TRY
	END FOR
END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION createTables()
	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[1]))
	CREATE TABLE users(
     user_id char(10),
     user_name varchar(30),
     user_level smallint,
     last_branch char(10),
     last_bs_job_no char(9),
     last_bs_job_link integer,
     printer_no smallint,
     logged_in char(1),
     email_address varchar(200),
     specimen_other char(4),
     home_branch char(4),
     spool_on char(1),
     user_password char(80),
     sms_no char(20),
     notify_types char(10),
     is_role char(1),
     recovery_email varchar(200),
     hide_user smallint,
     skip_email smallint,
     notification_read_dt datetime year to second)

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[2]))
	CREATE TABLE emp01(
			branch_code CHAR(2), short_code CHAR(4), full_name VARCHAR(30), productive CHAR(1), allow_job_complete CHAR(1),
			department CHAR(1), pay_method CHAR(1), std_hrs DECIMAL(5, 2), rate2_hrs DECIMAL(5, 2), rate3_hrs DECIMAL(5, 2),
			rate4_hrs DECIMAL(5, 2), breaks DECIMAL(5, 2), tsk1 CHAR(4), tsk2 CHAR(4), tsk3 CHAR(4), tsk4 CHAR(4),
			tsk5 CHAR(4), tsk6 CHAR(4), tsk7 CHAR(4), tsk8 CHAR(4), lockout SMALLINT, leave_date DATE,
			weighting DECIMAL(6, 2), met_p DECIMAL(6, 2), pan_p DECIMAL(6, 2), paint_p DECIMAL(6, 2), doc_location VARCHAR(100),
			cf_seq_no INTEGER, met_ata CHAR(1), pan_ata CHAR(1), paint_ata CHAR(1), user_id CHAR(10), image_flag CHAR(1))

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[3]))
	CREATE TABLE bra01(branch_code CHAR(2), branch_name VARCHAR(30))

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[4]))
create table device_login
  (
    emp_user char(10),
    branch_code char(2),
    app_name varchar(20),
    last_dev_id varchar(40),
    last_dev_id2 varchar(40),
    last_dev_ip varchar(80),
    last_ip varchar(80),
    last_login datetime year to second,
    last_logout datetime year to second,
    logout_method char(1),
    last_failed_attempt datetime year to second,
    failed_attempts smallint,
    logged_in char(1)
  );

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[5]))
create table job01
  (
    job_link serial not null ,
    branch_code char(2),
    job_number char(10),
    doc_location char(100),
    vehicle_index integer,
    vehicle_mileage char(7),
    vehicle_taxdisc char(20),
    vehicle_nf char(3),
    vehicle_nr char(3),
    vehicle_of char(3),
    vehicle_or char(3),
    vehicle_sp char(3),
    vehicle_arrive char(1),
    vehicle_depart char(1),
    on_site char(1),
    no_days_free smallint,
    hire_car char(1),
    hire_id char(10),
    hire_type char(1),
    contact_name char(40),
    contact_telephone char(20),
    insurer_contact char(40),
    insurer_telephone char(20),
    order_no char(20),
    estimator char(4),
    ad_job char(30),
    completed_by char(10),
    referral_ref char(10),
    job_invoiced char(1),
    inv_period decimal(5,2),
    hold_reason char(40),
    invoice char(1),
    last_contact_by char(10),
    group_code char(10),
    keytag char(10),
    list_set char(10),
    job_costed char(1),
    day_book char(1),
    created_date datetime year to fraction(3),
    created_by char(10),
    amended_date datetime year to fraction(3),
    amended_by char(10),
    taxed char(1),
    mileage_out char(7),
    driveable char(1),
    job_type char(1),
    drivers_name char(40),
    estimate_mileage char(10),
    ok_to_invoice char(1),
    taxed_until date,
    cf_seq_no integer,
    orig_caps_code char(25),
    orig_branch char(2),
    is_visible char(1),
    man_completed_by char(10),
    man_completed_date datetime year to fraction(3),
    man_completed_code char(1)
)

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[6]))
create table trim1
  (
    employee_code char(4),
    branch_code char(2),
    work_code char(4),
    command_code char(1),
    job_link integer,
    swipe_time datetime year to second,
    interrupt_flag char(1),
    interrupt_time datetime year to second,
    weighting decimal(6,2),
    pay_type char(1)
)

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[7]))
create table trim2 (
    txn_no serial not null ,
    txn_date date,
    txn_period decimal(5,2),
    start_datetime datetime year to second,
    end_datetime datetime year to second,
    interval_time interval hour(9) to minute,
    decimal_time decimal(6,2),
    actual_cost decimal(9,2),
    actual_time decimal(9,2),
    job_link integer,
    work_code char(4),
    employee_code char(4),
    branch_code char(2),
    start_command char(1),
    stop_command char(1),
    narrative_code char(1),
    p_status char(1),
    day_book char(1),
    weighting decimal(6,2),
    pay_type char(1),
    claimed decimal(9,2),
    toclaim decimal(9,2)
  );


	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[8]))
create table lists
  ( 
    internal_no serial not null ,
    list_no smallint,
    report_no smallint,
    list_type char(1),
    compulsory char(1),
    library char(1),
    list_output integer,
    analysis_code char(4),
    work_code char(4),
    work_group char(5),
    list_title char(30),
    job_sheet_title char(30),
    estimate_title char(30),
    invoice_title char(30),
    standard_sale decimal(6,2),
    weighting decimal(5,2),
    parts char(1),
    uplift char(1),
    auto_load char(1),
    auto_invoice char(1),
    auto_hours decimal(9,2),
    show_trim char(1),
    taxable char(1),
    taxcode smallint,
    protected char(1),
    department char(3),
    process_code integer
  )

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[9]))
create table lista
  (
    job_link integer,
    list_link integer,
    entry_no smallint,
    record_type char(1),
    description char(70),
    estimated_source char(1),
    estimated_date datetime year to fraction(3),
    estimated_rate decimal(6,2),
    estimated_hours decimal(6,2),
    estimated_total decimal(11,2),
    agreed_date datetime year to fraction(3),
    agreed_rate decimal(6,2),
    agreed_hours decimal(6,2),
    agreed_total decimal(11,2),
    discount_rate decimal(5,2),
    discount_hours decimal(9,2),
    invoice_total decimal(11,2),
    discount_total decimal(9,2),
    workshop_loading decimal(6,2),
    workshop_hours decimal(6,2),
    actual_hours decimal(6,2),
    actual_total decimal(11,2),
    p_status smallint
  );

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[10]))
create table vehicle
  (
    vehicle_index serial not null ,
    vehicle_id char(20),
    make char(20),
    model_name char(20),
    model_code char(20),
    vin char(20),
    colour_name char(20),
    colour_code char(20),
    engine_desc char(20),
    engine_no char(20),
    trans_type char(20),
    trans_no char(20),
    user1 char(30),
    user2 char(30),
    trim_name char(20),
    trim_code char(20),
    doors smallint,
    m_year integer,
    m_month integer,
    radio_code char(20),
    key_code char(20),
    last_used datetime year to fraction(3),
    last_amend datetime year to fraction(3)
  );

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[11]))
create table next_job
  (
    employee char(4),
    allocated datetime year to fraction(3),
    branch char(2),
    job_link integer,
    task integer,
    priority integer,
    taken datetime year to minute,
    resource char(4)
  );

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[12]))
create table lista_trim 
  (
    job_link integer,
    list_link integer,
    entry_no smallint,
    task_start datetime year to minute,
    task_end datetime year to minute,
    recorded_time decimal(9,2),
    claimed_time decimal(9,2),
    ata_completed_by char(4),
    ata_completed_date datetime year to fraction(3),
    man_completed_by char(4),
    man_completed_date datetime year to fraction(3),
    man_completed_code char(1)
  );

	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[13]))
create table job_dates (
    job_link integer,
    job_cancelled1 datetime year to fraction(3),
    job_cancelled datetime year to fraction(3),
    uncancel1 datetime year to fraction(3),
    uncancel datetime year to fraction(3),
    incident1 datetime year to fraction(3),
    incident datetime year to fraction(3),
    repairer_notified1 datetime year to fraction(3),
    repairer_notified datetime year to fraction(3),
    customer_cont1 datetime year to fraction(3),
    customer_cont datetime year to fraction(3),
    estimated1 datetime year to fraction(3),
    estimated datetime year to fraction(3),
    authorised1 datetime year to fraction(3),
    authorised datetime year to fraction(3),
    onsite1 datetime year to fraction(3),
    onsite datetime year to fraction(3),
    recovery1 datetime year to fraction(3),
    recovery datetime year to fraction(3),
    cv_out1 datetime year to fraction(3),
    cv_out datetime year to fraction(3),
    cv_back1 datetime year to fraction(3),
    cv_back datetime year to fraction(3),
    sms_sent1 datetime year to fraction(3),
    sms_sent datetime year to fraction(3),
    in_progress1 datetime year to fraction(3),
    in_progress datetime year to fraction(3),
    parts_ordered1 datetime year to fraction(3),
    parts_ordered datetime year to fraction(3),
    parts_delivered1 datetime year to fraction(3),
    parts_delivered datetime year to fraction(3),
    sched_ws_comp1 datetime year to fraction(3),
    sched_ws_comp datetime year to fraction(3),
    ws_comp1 datetime year to fraction(3),
    ws_comp datetime year to fraction(3),
    invoiced1 datetime year to fraction(3),
    invoiced datetime year to fraction(3),
    jobsheet_printed1 datetime year to fraction(3),
    jobsheet_printed datetime year to fraction(3),
    inspection_book1 datetime year to fraction(3),
    inspection_book datetime year to fraction(3),
    inspected1 datetime year to fraction(3),
    inspected datetime year to fraction(3),
    write_off1 datetime year to fraction(3),
    write_off datetime year to fraction(3),
    booked_in_ws1 datetime year to fraction(3),
    booked_in_ws datetime year to fraction(3),
    sched_onsite1 datetime year to fraction(3),
    sched_onsite datetime year to fraction(3),
    sched_handover1 datetime year to fraction(3),
    sched_handover datetime year to fraction(3),
    handover1 datetime year to fraction(3),
    handover datetime year to fraction(3),
    invoice_paid1 datetime year to fraction(3),
    invoice_paid datetime year to fraction(3),
    job_hold1 datetime year to fraction(3),
    job_hold datetime year to fraction(3),
    job_unhold1 datetime year to fraction(3),
    job_unhold datetime year to fraction(3),
    sat_note_prt1 datetime year to fraction(3),
    sat_note_prt datetime year to fraction(3),
    xs_receipt_prt1 datetime year to fraction(3),
    xs_receipt_prt datetime year to fraction(3),
    estimate_booked1 datetime year to fraction(3),
    estimate_booked datetime year to fraction(3),
    job_closed1 datetime year to fraction(3),
    job_closed datetime year to fraction(3),
    user_live1 datetime year to fraction(3),
    user_live datetime year to fraction(3),
    parts_request1 datetime year to fraction(3),
    parts_request datetime year to fraction(3),
    customer_accept1 datetime year to fraction(3),
    customer_accept datetime year to fraction(3),
    job_accepted1 datetime year to fraction(3),
    job_accepted datetime year to fraction(3),
    est_booking_made1 datetime year to fraction(3),
    est_booking_made datetime year to fraction(3),
    cust_req_return1 datetime year to fraction(3),
    cust_req_return datetime year to fraction(3),
    sched_handover_set1 datetime year to fraction(3),
    sched_handover_set datetime year to fraction(3),
    booked_out1 datetime year to fraction(3),
    booked_out datetime year to fraction(3),
    next_contact1 datetime year to fraction(3),
    next_contact datetime year to fraction(3),
    awaiting_liability1 datetime year to fraction(3),
    awaiting_liability datetime year to fraction(3),
    auth_requested1 datetime year to fraction(3),
    auth_requested datetime year to fraction(3)
  );


	CALL lib.log(1, SFMT("Create %1 ...", m_tabs[14]))
create table parts
  (
    job_link integer,
    list_link integer,
    entry_no smallint,
    quantity decimal(5,2),
    description char(35),
    copy_out char(1),
    stock_no char(20),
    order_date datetime year to fraction(3),
    order_no char(10),
    supplier_acc char(6),
    cost decimal(9,2),
    vat decimal(9,2),
    surcharge decimal(9,2),
    pdiscount decimal(6,2),
    p_extended decimal(9,2),
    part_type char(1),
    no_delivered decimal(5,2),
    supply_date datetime year to fraction(3),
    delivery_no char(20),
    invoice_no char(12),
    sale decimal(9,2),
    s_extended decimal(9,2),
    sdiscount decimal(6,2),
    discount decimal(9,2),
    p_status char(1),
    day_book char(1),
    l_status char(1),
    history integer,
    mkup decimal(9,2),
    delivered char(1),
    bin_loc char(20),
    add_after_auth char(1),
    supplementary char(1),
    analysis_code char(4),
    betterment decimal(9,2),
    vat_code smallint,
    show_on_inv char(1),
    se_retval decimal(9,2),
    back_order char(1),
    back_order_dt date,
    back_order_code char(4)
  );


END FUNCTION
--------------------------------------------------------------------------------------------------------------
FUNCTION insertTestData()
	insert into users values('test','Testing',9,'A',NULL,NULL,NULL,'N',NULL,NULL,'A',NULL,'test',NULL,NULL,NULL,NULL,0,0,CURRENT_TIMESTAMP);
	insert into emp01 values('A','TEST','Test User','Y','N','H','A',0,0,0,0,0,'MECH','STRP','RFIT','PANL','','','','',0,NULL,100.0,100.0,0.0,0.0,'/employees/A/NM99',2,'N','N','N','test','Y');
	insert into bra01 values( 'A','Branch A');
END FUNCTION
--------------------------------------------------------------------------------------------------------------