SET search_path TO alexa_project;

-- DROP Statements with Error Handling
DO $$ BEGIN
    -- Drop triggers
    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'user_update_trigger') THEN
        EXECUTE 'DROP TRIGGER user_update_trigger ON "User";';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'device_usage_audit_trigger') THEN
        EXECUTE 'DROP TRIGGER device_usage_audit_trigger ON "Device";';
    END IF;

    -- Drop sequences (automatically handles dependencies via CASCADE)
    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'user_id_seq') THEN
        EXECUTE 'DROP SEQUENCE user_id_seq CASCADE;';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'command_id_seq') THEN
        EXECUTE 'DROP SEQUENCE command_id_seq CASCADE;';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'device_id_seq') THEN
        EXECUTE 'DROP SEQUENCE device_id_seq CASCADE;';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'skill_id_seq') THEN
        EXECUTE 'DROP SEQUENCE skill_id_seq CASCADE;';
    END IF;

    -- Drop views and audit tables
    IF EXISTS (SELECT 1 FROM information_schema.views WHERE table_name = 'userdevices') THEN
        EXECUTE 'DROP VIEW userdevices;';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'UserAuditLog') THEN
        EXECUTE 'DROP TABLE UserAuditLog;';
    END IF;

    IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'DeviceUsageAudit') THEN
        EXECUTE 'DROP TABLE DeviceUsageAudit;';
    END IF;

    -- Drop remaining tables
    EXECUTE 'DROP TABLE IF EXISTS "UserSkill", "DeviceCommand", "SkillUsage", "Interaction", "Device", "VoiceCommand", "Skill", "User" CASCADE;';
END $$;

-- Recreate Sequences
CREATE SEQUENCE IF NOT EXISTS user_id_seq START 100 INCREMENT 1;
CREATE SEQUENCE IF NOT EXISTS command_id_seq START 200 INCREMENT 1;
CREATE SEQUENCE IF NOT EXISTS device_id_seq START 300 INCREMENT 1;
CREATE SEQUENCE IF NOT EXISTS skill_id_seq START 400 INCREMENT 1;

-- Recreate Tables
CREATE TABLE IF NOT EXISTS "User" (
    UserID INT DEFAULT NEXTVAL('user_id_seq') PRIMARY KEY,
    Name VARCHAR(100),
    Email VARCHAR(100) UNIQUE,
    RegistrationDate DATE,
    DeviceType VARCHAR(50),
    Location VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS "Device" (
    DeviceID INT DEFAULT NEXTVAL('device_id_seq') PRIMARY KEY,
    DeviceName VARCHAR(100),
    DeviceModel VARCHAR(50),
    UserID INT NOT NULL,
    LastUsed TIMESTAMP,
    PurchaseDate DATE,
    CONSTRAINT fk_user_device FOREIGN KEY (UserID) REFERENCES "User" (UserID) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "VoiceCommand" (
    CommandID INT DEFAULT NEXTVAL('command_id_seq') PRIMARY KEY,
    CommandText VARCHAR(255),
    Timestamp TIMESTAMP,
    ResponseTime INTEGER,
    SuccessStatus VARCHAR(50),
    VoiceProfile VARCHAR(50),
    UserID INT NOT NULL,
    CONSTRAINT fk_user FOREIGN KEY (UserID) REFERENCES "User" (UserID) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "Skill" (
    SkillID INT DEFAULT NEXTVAL('skill_id_seq') PRIMARY KEY,
    SkillName VARCHAR(100),
    SkillCategory VARCHAR(50),
    LaunchCount INT,
    UserRating FLOAT,
    Developer VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS "Interaction" (
    InteractionID SERIAL PRIMARY KEY,
    UserID INT NOT NULL,
    CommandID INT NOT NULL,
    SkillID INT,
    Duration INTEGER,
    InteractionDate DATE,
    CONSTRAINT fk_command FOREIGN KEY (CommandID) REFERENCES "VoiceCommand" (CommandID) ON DELETE CASCADE,
    CONSTRAINT fk_user_interaction FOREIGN KEY (UserID) REFERENCES "User" (UserID) ON DELETE CASCADE,
    CONSTRAINT fk_skill FOREIGN KEY (SkillID) REFERENCES "Skill" (SkillID) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "UserSkill" (
    UserID INT NOT NULL,
    SkillID INT NOT NULL,
    DateEnabled DATE,
    PRIMARY KEY (UserID, SkillID),
    CONSTRAINT fk_user_skill FOREIGN KEY (UserID) REFERENCES "User" (UserID) ON DELETE CASCADE,
    CONSTRAINT fk_skill_user FOREIGN KEY (SkillID) REFERENCES "Skill" (SkillID) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "DeviceCommand" (
    DeviceID INT NOT NULL,
    CommandID INT NOT NULL,
    UsageCount INT,
    PRIMARY KEY (DeviceID, CommandID),
    CONSTRAINT fk_device FOREIGN KEY (DeviceID) REFERENCES "Device" (DeviceID) ON DELETE CASCADE,
    CONSTRAINT fk_command_device FOREIGN KEY (CommandID) REFERENCES "VoiceCommand" (CommandID) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "SkillUsage" (
    SkillID INT NOT NULL,
    InteractionID INT NOT NULL,
    UsageFrequency INT,
    PRIMARY KEY (SkillID, InteractionID),
    CONSTRAINT fk_skill_usage FOREIGN KEY (SkillID) REFERENCES "Skill" (SkillID) ON DELETE CASCADE,
    CONSTRAINT fk_interaction_skill FOREIGN KEY (InteractionID) REFERENCES "Interaction" (InteractionID) ON DELETE CASCADE
);

-- Recreate Audit Tables
CREATE TABLE IF NOT EXISTS UserAuditLog (
    AuditID SERIAL PRIMARY KEY,
    UserID INT NOT NULL,
    OldName VARCHAR(100),
    NewName VARCHAR(100),
    UpdateTimestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS DeviceUsageAudit (
    AuditID SERIAL PRIMARY KEY,
    DeviceID INT NOT NULL,
    UserID INT,
    OldLastUsed TIMESTAMP,
    NewLastUsed TIMESTAMP,
    ChangeTimestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Recreate Triggers
CREATE OR REPLACE FUNCTION log_user_update()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO UserAuditLog (UserID, OldName, NewName)
    VALUES (OLD.UserID, OLD.Name, NEW.Name);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER user_update_trigger
AFTER UPDATE ON "User"
FOR EACH ROW
EXECUTE FUNCTION log_user_update();

CREATE OR REPLACE FUNCTION log_device_usage()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO DeviceUsageAudit (DeviceID, UserID, OldLastUsed, NewLastUsed)
    VALUES (OLD.DeviceID, OLD.UserID, OLD.LastUsed, NEW.LastUsed);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER device_usage_audit_trigger
AFTER UPDATE OF LastUsed ON "Device"
FOR EACH ROW
EXECUTE FUNCTION log_device_usage();

-- Recreate View
CREATE OR REPLACE VIEW userdevices AS
SELECT u.Name, u.Email, u.DeviceType, u.Location, d.DeviceName, d.DeviceModel
FROM "User" u
JOIN "Device" d ON u.UserID = d.UserID;


delete from "Device";
delete from "DeviceCommand";
delete from "Interaction";
delete from "Skill";
delete from "SkillUsage";
delete from "User";
delete from "UserSkill";
delete from "VoiceCommand";
delete from "deviceusageaudit";
delete from "userauditlog";


-- Insert 10 values into the User table (without specifying UserID)
INSERT INTO "User" (Name, Email, RegistrationDate, DeviceType, Location)
VALUES
    ('John Doe', 'john.doe@example.com', '2023-01-01', 'Smartphone', 'New York'),
    ('Jane Smith', 'jane.smith@example.com', '2023-02-15', 'Tablet', 'Los Angeles'),
    ('Alice Johnson', 'alice.johnson@example.com', '2023-03-20', 'Laptop', 'Chicago'),
    ('Bob Brown', 'bob.brown@example.com', '2023-04-10', 'Smartwatch', 'Houston'),
    ('Charlie Davis', 'charlie.davis@example.com', '2023-05-22', 'Smartphone', 'San Francisco'),
    ('David Wilson', 'david.wilson@example.com', '2023-06-05', 'Tablet', 'Dallas'),
    ('Eve Martinez', 'eve.martinez@example.com', '2023-07-12', 'Laptop', 'Seattle'),
    ('Frank White', 'frank.white@example.com', '2023-08-01', 'Smartwatch', 'Boston'),
    ('Grace Lee', 'grace.lee@example.com', '2023-09-18', 'Smartphone', 'Austin'),
    ('Hank Moore', 'hank.moore@example.com', '2023-10-25', 'Tablet', 'Denver');


-- Insert 10 values into the Device table
INSERT INTO "Device" (DeviceName, DeviceModel, UserID, LastUsed, PurchaseDate)
VALUES
    ('iPhone 14', 'Smartphone', 121, '2023-12-01', '2023-01-01'),
    ('iPad Pro', 'Tablet', 122, '2023-12-01', '2023-02-15'),
    ('MacBook Pro', 'Laptop', 123, '2023-12-01', '2023-03-20'),
    ('Apple Watch', 'Smartwatch', 124, '2023-12-01', '2023-04-10'),
    ('Samsung Galaxy S22', 'Smartphone', 125, '2023-12-01', '2023-05-22'),
    ('Galaxy Tab S8', 'Tablet', 126, '2023-12-01', '2023-06-05'),
    ('Dell XPS 13', 'Laptop', 127, '2023-12-01', '2023-07-12'),
    ('Garmin Venu', 'Smartwatch', 128, '2023-12-01', '2023-08-01'),
    ('Google Pixel 6', 'Smartphone', 129, '2023-12-01', '2023-09-18'),
    ('Samsung Galaxy Tab A8', 'Tablet', 130, '2023-12-01', '2023-10-25');



-- Insert 10 values into the VoiceCommand table
INSERT INTO "VoiceCommand" (CommandText, Timestamp, ResponseTime, SuccessStatus, VoiceProfile, UserID)
VALUES
    ('Play music', '2023-12-01 10:00:00', 200, 'Success', 'Default', 121),
    ('Set alarm', '2023-12-01 10:05:00', 150, 'Success', 'Default', 122),
    ('Open browser', '2023-12-01 10:10:00', 180, 'Success', 'Default', 123),
    ('Start workout', '2023-12-01 10:15:00', 160, 'Success', 'Default', 124),
    ('Send message', '2023-12-01 10:20:00', 140, 'Success', 'Default', 125),
    ('Read email', '2023-12-01 10:25:00', 220, 'Success', 'Default', 126),
    ('Turn on light', '2023-12-01 10:30:00', 190, 'Success', 'Default', 127),
    ('Set timer', '2023-12-01 10:35:00', 170, 'Success', 'Default', 128),
    ('Make a call', '2023-12-01 10:40:00', 180, 'Success', 'Default', 129),
    ('Search news', '2023-12-01 10:45:00', 200, 'Success', 'Default', 130);


-- Insert 10 values into the Skill table
INSERT INTO "Skill" (SkillName, SkillCategory, LaunchCount, UserRating, Developer)
VALUES
    ('Spotify Music', 'Entertainment', 50, 4.5, 'Spotify'),
    ('Google Assistant', 'Utility', 100, 4.7, 'Google'),
    ('Apple Siri', 'Utility', 80, 4.6, 'Apple'),
    ('Fitness Tracker', 'Health', 30, 4.4, 'Garmin'),
    ('Netflix', 'Entertainment', 120, 4.8, 'Netflix'),
    ('Amazon Alexa', 'Utility', 150, 4.9, 'Amazon'),
    ('Zoom', 'Communication', 70, 4.6, 'Zoom Video Communications'),
    ('WhatsApp', 'Communication', 110, 4.7, 'Meta'),
    ('Google Maps', 'Navigation', 200, 4.9, 'Google'),
    ('Slack', 'Communication', 40, 4.5, 'Slack Technologies');




INSERT INTO "Interaction" (InteractionID, UserID, CommandID, Duration, InteractionDate)
VALUES
    (1, 121, 230, 5, '2023-12-01'),
    (2, 122, 231, 4, '2023-12-01'),
    (3, 123, 232, 6, '2023-12-01'),
    (4, 124, 233, 5, '2023-12-01'),
    (5, 125, 234, 7, '2023-12-01'),
    (6, 126, 235, 8, '2023-12-01'),
    (7, 127, 236, 3, '2023-12-01'),
    (8, 128, 237, 9, '2023-12-01'),
    (9, 129, 238, 6, '2023-12-01'),
    (10, 130, 239, 4, '2023-12-01');


-- Insert values into the UserSkill table
INSERT INTO "UserSkill" (UserID, SkillID, DateEnabled)
VALUES
    (121, 410, '2023-01-01'),
    (122, 411, '2023-02-15'),
    (123, 412, '2023-03-20'),
    (124, 413, '2023-04-10'),
    (125, 414, '2023-05-22'),
    (126, 415, '2023-06-05'),
    (127, 416, '2023-07-12'),
    (128, 417, '2023-08-01'),
    (129, 418, '2023-09-18'),
    (130, 419, '2023-10-25');

-- Insert values into the DeviceCommand table
INSERT INTO "DeviceCommand" (DeviceID, CommandID, UsageCount)
VALUES
    (345, 230, 10),
    (346, 231, 5),
    (347, 232, 12),
    (348, 233, 8),
    (349, 234, 7),
    (350, 235, 15),
    (351, 236, 9),
    (352, 237, 6),
    (353, 238, 4),
    (354, 239, 14);


-- Insert values into the SkillUsage table
INSERT INTO "SkillUsage" (SkillID, InteractionID, UsageFrequency)
VALUES
    (410, 1, 3),
    (411, 2, 5),
    (412, 3, 2),
    (413, 4, 4),
    (414, 5, 6),
    (415, 6, 7),
    (416, 7, 8),
    (417, 8, 1),
    (418, 9, 3),
    (419, 10, 5);



CREATE VIEW "UserDeviceInfoView" AS
SELECT 
    u.UserID,
    u.Name AS UserName,
    u.Email,
    u.DeviceType,
    u.Location,
    u.RegistrationDate,
    d.DeviceID,
    d.DeviceName,
    d.DeviceModel,
    d.LastUsed,
    d.PurchaseDate
FROM "User" u
JOIN "Device" d ON u.UserID = d.UserID;



-- Business Case: Retrieve all information about users to perform an audit of their registration data.

SELECT * FROM "User";


-- Business Case: Retrieve the name, email, device type, location, and registration date for all users to prepare a marketing campaign.

SELECT Name, Email, DeviceType, Location, RegistrationDate FROM "User";


-- Business Case: Assume there is a view named UserDeviceInfoView that provides a summary of user and device information. Retrieve all data for further analysis.

SELECT * FROM "UserDeviceInfoView";

-- Business Case: Retrieve all user details along with the devices they own.

SELECT * 
FROM "User" u
JOIN "Device" d ON u.UserID = d.UserID;

-- Business Case: Retrieve all skills sorted by their user rating to identify the best-rated skills.

SELECT * 
FROM "Skill"
ORDER BY UserRating DESC;

-- Consider a scenario where you want to track the usage of devices by users and the duration of their interactions with the system. Your goal is to understand which users are using which devices and how long they interact with the system. This kind of information is useful for optimizing user experience and managing resources (e.g., devices, interaction types) based on actual usage patterns.

-- For example, imagine you are working for a company that sells smart devices. You want to analyze how often users are interacting with their devices and what type of devices are most popular. By combining data from the User, Device, and Interaction tables, you can gain insights into these patterns and optimize marketing campaigns or device updates.
SELECT 
    u.UserID,
    u.Name AS UserName,
    d.DeviceName,
    d.LastUsed,
    i.Duration
FROM "User" u
JOIN "Device" d ON u.UserID = d.UserID
JOIN "Interaction" i ON u.UserID = i.UserID
LIMIT 3;

-- Imagine you are working for a company that manufactures and sells various smart devices. The company wants to understand which combinations of users and devices are most commonly associated with specific commands (like "Play music," "Set alarm," etc.). This analysis will help to optimize the development and marketing efforts for specific devices and commands, ensuring they meet user preferences.

-- In this case, you want to eliminate any duplicate combinations of users, devices, and commands to identify unique user-device-command interactions. This will provide insights into which commands are popular across different devices and help prioritize feature improvements or promotional campaigns.

SELECT DISTINCT 
    u.Name AS UserName,
    d.DeviceName,
    vc.CommandText
FROM "User" u
JOIN "Device" d ON u.UserID = d.UserID
JOIN "VoiceCommand" vc ON u.UserID = vc.UserID
LIMIT 3;

-- The company wants to analyze the usage patterns of voice commands across different devices to determine which voice commands are most frequently used by customers. This information will be used to improve user experience by identifying the most popular commands, allowing for focused updates and marketing strategies based on device types (e.g., smartphone, tablet, laptop, smartwatch).

SELECT 
    d.DeviceName,
    vc.CommandText
FROM "Device" d
JOIN "VoiceCommand" vc ON d.UserID = vc.UserID
ORDER BY d.DeviceName, vc.CommandText;


-- The company wants to retrieve details of devices that have been used by users who are located in either "New York" or "San Francisco." This information can help determine which devices are more commonly used in specific cities, assisting in targeted marketing campaigns.

SELECT 
    d.DeviceName,
    d.DeviceModel,
    u.Name,
    u.Location
FROM "Device" d
JOIN "User" u ON d.UserID = u.UserID
WHERE u.Location IN ('New York', 'San Francisco');

-- The company wants to analyze the length of device model names to understand how concise or detailed the device naming conventions are. This can help in simplifying product naming in the future.

SELECT 
    DeviceName,
    LENGTH(DeviceModel) AS DeviceModelLength
FROM "Device";

-- The company wants to remove an old device from the database. In this case, we will delete a record for a device that has been discontinued, and then verify the change.

SELECT * FROM "Device" WHERE DeviceName = 'iPhone 14';
DELETE FROM "Device" WHERE DeviceName = 'iPhone 14';
SELECT * FROM "Device" WHERE DeviceName = 'iPhone 14';

-- The company needs to update the LastUsed date for a device after it is used by the user in a new session. The goal is to keep track of when the device was last used.

SELECT * FROM "Device" WHERE DeviceName = 'iPad Pro';

UPDATE "Device" 
SET LastUsed = '2026-12-02'
WHERE DeviceName = 'iPad Pro';

SELECT * FROM "Device" WHERE DeviceName = 'iPad Pro';

-- The company wants to find out which device models are the most popular in each city. This will help them tailor marketing and inventory strategies by location.

SELECT 
    u.Location,
    d.DeviceModel,
    COUNT(d.DeviceID) AS DeviceCount
FROM "Device" d
JOIN "User" u ON d.UserID = u.UserID
GROUP BY u.Location, d.DeviceModel
ORDER BY u.Location, DeviceCount DESC;

-- Advanced Query 2: List all users who have used a specific voice command ("Send message")

SELECT DISTINCT u.Name, u.Email
FROM "User" u
JOIN "VoiceCommand" vc ON u.UserID = vc.UserID
WHERE vc.CommandText = 'Send message'


