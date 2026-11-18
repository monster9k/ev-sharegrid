-- Kích hoạt tiện ích mở rộng PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- 1. app_user
CREATE TABLE app_user (
    user_id BIGSERIAL PRIMARY KEY,
    role VARCHAR(20) NOT NULL CHECK (role IN ('USER', 'HOST', 'ADMIN')),
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    google_id VARCHAR(100),
    reliability_score NUMERIC(5,2) DEFAULT 95.00,
    status VARCHAR(20) DEFAULT 'ACTIVE',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. vehicle_model
CREATE TABLE vehicle_model (
    model_id BIGSERIAL PRIMARY KEY,
    brand VARCHAR(50) NOT NULL,
    model_name VARCHAR(50) NOT NULL,
    vehicle_type VARCHAR(20) CHECK (vehicle_type IN ('CAR', 'MOTORBIKE')),
    connector_type VARCHAR(50) CHECK (connector_type IN ('CCS2', 'Type2', 'AC_HOME', 'CHAdeMO')),
    source_type VARCHAR(20) DEFAULT 'REAL',
    source_ref TEXT,
    battery_kwh NUMERIC(10,3) NOT NULL,
    max_kw NUMERIC(10,3) NOT NULL,
    max_ac_kw NUMERIC(10,3),
    max_dc_kw NUMERIC(10,3),
    standard_charger_kw NUMERIC(10,3),
    data_note TEXT
);

-- 3. vehicle
CREATE TABLE vehicle (
    vehicle_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES app_user(user_id) ON DELETE CASCADE,
    model_id BIGINT REFERENCES vehicle_model(model_id),
    plate_number VARCHAR(20) UNIQUE NOT NULL,
    nickname VARCHAR(50),
    default_soc_target NUMERIC(5,2) DEFAULT 80.00,
    is_default BOOLEAN DEFAULT FALSE
);

-- 4. grid_cluster
CREATE TABLE grid_cluster (
    cluster_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    province VARCHAR(50) NOT NULL,
    timezone VARCHAR(50) DEFAULT 'Asia/Ho_Chi_Minh',
    status VARCHAR(20) DEFAULT 'ACTIVE',
    h3_index VARCHAR(20),
    centroid_lat NUMERIC(9,6),
    centroid_lng NUMERIC(9,6),
    boundary GEOMETRY(MultiPolygon, 4326),
    grid_limit_kw NUMERIC(12,3) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. charging_station
CREATE TABLE charging_station (
    station_id BIGSERIAL PRIMARY KEY,
    cluster_id BIGINT REFERENCES grid_cluster(cluster_id),
    owner_id BIGINT REFERENCES app_user(user_id),
    name VARCHAR(100) NOT NULL,
    address TEXT NOT NULL,
    province VARCHAR(50) NOT NULL,
    area_label VARCHAR(50),
    supported_vehicle_type VARCHAR(20) DEFAULT 'ALL',
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'ACTIVE', 'MAINTENANCE', 'OFFLINE')),
    ocpp_id VARCHAR(50),
    phone VARCHAR(20),
    osm_id VARCHAR(50),
    source_type VARCHAR(20) DEFAULT 'SURVEY',
    source_ref TEXT,
    lat NUMERIC(9,6),
    lng NUMERIC(9,6),
    location GEOMETRY(Point, 4326),
    open_time TIME DEFAULT '00:00',
    close_time TIME DEFAULT '23:59',
    is_24h BOOLEAN DEFAULT TRUE,
    verified BOOLEAN DEFAULT FALSE,
    station_power_kw NUMERIC(12,3) NOT NULL,
    service_fee_vnd NUMERIC(14,2) DEFAULT 0.00,
    price_override_vnd_kwh NUMERIC(14,2),
    max_session_minutes INTEGER DEFAULT 360,
    rating NUMERIC(3,2),
    listed_network VARCHAR(50),
    listed_port_count INTEGER,
    listed_max_port_kw NUMERIC(10,3),
    qa_notes TEXT
);
CREATE INDEX idx_charging_station_location ON charging_station USING GIST(location);

-- 6. port
CREATE TABLE port (
    port_id BIGSERIAL PRIMARY KEY,
    station_id BIGINT REFERENCES charging_station(station_id) ON DELETE CASCADE,
    port_code VARCHAR(20) NOT NULL,
    connector_type VARCHAR(20) NOT NULL,
    control_type VARCHAR(20) CHECK (control_type IN ('CONTINUOUS', 'ON_OFF_SWITCH')),
    status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'MAINTENANCE', 'OFFLINE')),
    min_power_kw NUMERIC(10,3) DEFAULT 0.000,
    max_power_kw NUMERIC(10,3) NOT NULL,
    CONSTRAINT uk_station_port_code UNIQUE (station_id, port_code)
);

-- 7. tariff_window
-- TODO: source_ref must contain the verified EVN decision number and date.
-- Leave it NULL until the official document is supplied; do not infer an identifier.
CREATE TABLE tariff_window (
    tariff_id BIGSERIAL PRIMARY KEY,
    cluster_id BIGINT REFERENCES grid_cluster(cluster_id),
    day_type VARCHAR(20) CHECK (day_type IN ('WEEKDAY', 'WEEKEND', 'HOLIDAY')),
    band VARCHAR(20) CHECK (band IN ('OFF_PEAK', 'NORMAL', 'PEAK')),
    source_ref VARCHAR(100),
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    price_vnd_kwh NUMERIC(14,2) NOT NULL,
    valid_from DATE DEFAULT CURRENT_DATE,
    valid_to DATE DEFAULT '2099-12-31'
);

-- 8. simulation_scenario
CREATE TABLE simulation_scenario (
    scenario_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    source_type VARCHAR(20) DEFAULT 'SIMULATED',
    seed INT DEFAULT 42,
    registry_users INT DEFAULT 100000,
    active_requests INT NOT NULL,
    config_json JSONB,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 9. optimization_job
CREATE TABLE optimization_job (
    job_id BIGSERIAL PRIMARY KEY,
    cluster_id BIGINT REFERENCES grid_cluster(cluster_id),
    target_version BIGINT NOT NULL,
    status VARCHAR(20) DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'RUNNING', 'COMPLETED', 'FAILED')),
    events_count INT DEFAULT 1,
    attempt_count INT DEFAULT 0,
    queued_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    lease_expires_at TIMESTAMPTZ,
    worker_id VARCHAR(50)
);

-- 10. charging_request
CREATE TABLE charging_request (
    request_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES app_user(user_id),
    vehicle_id BIGINT REFERENCES vehicle(vehicle_id),
    cluster_id BIGINT REFERENCES grid_cluster(cluster_id),
    station_id BIGINT REFERENCES charging_station(station_id),
    scenario_id BIGINT REFERENCES simulation_scenario(scenario_id),
    idempotency_key VARCHAR(100) UNIQUE,
    arrival_time TIMESTAMPTZ NOT NULL,
    departure_time TIMESTAMPTZ NOT NULL,
    soc_now NUMERIC(5,2) NOT NULL,
    soc_target NUMERIC(5,2) NOT NULL,
    battery_kwh_snapshot NUMERIC(10,3) NOT NULL,
    max_kw_snapshot NUMERIC(10,3) NOT NULL,
    eta NUMERIC(4,3) DEFAULT 0.90,
    energy_needed_kwh NUMERIC(14,6) NOT NULL,
    shortfall_kwh NUMERIC(14,6) DEFAULT 0.0,
    priority_weight NUMERIC(8,3) DEFAULT 1.0,
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SCHEDULED', 'CONFIRMED', 'CHARGING', 'DONE', 'CANCELLED', 'NO_SHOW', 'FAILED')),
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_request_soc CHECK (soc_now < soc_target AND soc_target <= 100),
    CONSTRAINT chk_request_time CHECK (departure_time > arrival_time)
);

-- 11. optimization_run
CREATE TABLE optimization_run (
    run_id BIGSERIAL PRIMARY KEY,
    cluster_id BIGINT REFERENCES grid_cluster(cluster_id),
    scenario_id BIGINT REFERENCES simulation_scenario(scenario_id),
    job_id BIGINT REFERENCES optimization_job(job_id),
    algorithm VARCHAR(50) NOT NULL,
    trigger_type VARCHAR(50) DEFAULT 'NEW_BOOKING',
    status VARCHAR(20) CHECK (status IN ('OPTIMAL', 'FEASIBLE', 'FALLBACK', 'INFEASIBLE', 'ERROR')),
    code_version VARCHAR(50) DEFAULT 'v1.0.0',
    started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    solve_ms INT NOT NULL,
    seed INT DEFAULT 42,
    slot_minutes INT DEFAULT 15,
    n_requests INT NOT NULL,
    weights_json JSONB,
    input_json JSONB,
    kpi_json JSONB
);

-- 12. run_request
CREATE TABLE run_request (
    run_id BIGINT REFERENCES optimization_run(run_id) ON DELETE CASCADE,
    request_id BIGINT REFERENCES charging_request(request_id) ON DELETE CASCADE,
    allocated_kwh NUMERIC(14,6) NOT NULL,
    shortfall_kwh NUMERIC(14,6) DEFAULT 0.0,
    expected_soc NUMERIC(5,2) NOT NULL,
    estimated_cost_vnd NUMERIC(14,2) NOT NULL,
    explanation TEXT,
    PRIMARY KEY (run_id, request_id)
);

-- 13. schedule
CREATE TABLE schedule (
    schedule_id BIGSERIAL PRIMARY KEY,
    run_id BIGINT REFERENCES optimization_run(run_id),
    request_id BIGINT REFERENCES charging_request(request_id),
    port_id BIGINT REFERENCES port(port_id),
    slot_start TIMESTAMPTZ NOT NULL,
    power_kw NUMERIC(10,6) NOT NULL,
    version INT DEFAULT 1,
    is_active BOOLEAN DEFAULT TRUE
);
CREATE UNIQUE INDEX idx_schedule_active_port_slot ON schedule (port_id, slot_start) WHERE (is_active = TRUE);

-- 14. charging_session
CREATE TABLE charging_session (
    session_id BIGSERIAL PRIMARY KEY,
    request_id BIGINT REFERENCES charging_request(request_id),
    port_id BIGINT REFERENCES port(port_id),
    start_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    end_time TIMESTAMPTZ,
    energy_kwh NUMERIC(14,6) DEFAULT 0.0,
    soc_start NUMERIC(5,2),
    soc_end NUMERIC(5,2),
    cost_energy_vnd NUMERIC(14,2) DEFAULT 0.0,
    cost_service_vnd NUMERIC(14,2) DEFAULT 0.0,
    total_vnd NUMERIC(14,2) DEFAULT 0.0,
    stop_reason VARCHAR(50),
    status VARCHAR(20) DEFAULT 'IN_PROGRESS',
    is_simulated BOOLEAN DEFAULT TRUE
);

-- 15. notification
CREATE TABLE notification (
    notif_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES app_user(user_id),
    request_id BIGINT REFERENCES charging_request(request_id),
    type VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body TEXT NOT NULL,
    channel VARCHAR(20) DEFAULT 'APP_PUSH',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    sent_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ
);

-- 16. forecast_model
CREATE TABLE forecast_model (
    model_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    version VARCHAR(20) NOT NULL,
    algorithm VARCHAR(50) NOT NULL,
    artifact_path TEXT,
    status VARCHAR(20) DEFAULT 'ACTIVE',
    trained_until TIMESTAMPTZ,
    metrics_json JSONB
);

-- 17. demand_forecast
CREATE TABLE demand_forecast (
    forecast_id BIGSERIAL PRIMARY KEY,
    cluster_id BIGINT REFERENCES grid_cluster(cluster_id),
    model_id BIGINT REFERENCES forecast_model(model_id),
    generated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    hour_start TIMESTAMPTZ NOT NULL,
    pred_arrivals NUMERIC(12,3) NOT NULL
);

-- 18. benchmark_result
CREATE TABLE benchmark_result (
    benchmark_id BIGSERIAL PRIMARY KEY,
    scenario_id BIGINT REFERENCES simulation_scenario(scenario_id),
    run_id BIGINT REFERENCES optimization_run(run_id),
    algorithm VARCHAR(50) NOT NULL,
    repeat_no INT DEFAULT 1,
    metrics_json JSONB NOT NULL,
    measured_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_scenario_algo_repeat UNIQUE (scenario_id, algorithm, repeat_no)
);

-- 19. outbox_event
CREATE TABLE outbox_event (
    event_id BIGSERIAL PRIMARY KEY,
    cluster_id BIGINT REFERENCES grid_cluster(cluster_id),
    aggregate_type VARCHAR(50) NOT NULL,
    aggregate_id BIGINT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload_json JSONB NOT NULL,
    dedupe_key VARCHAR(100) UNIQUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    published_at TIMESTAMPTZ,
    attempts INT DEFAULT 0,
    status VARCHAR(20) DEFAULT 'PENDING'
);
