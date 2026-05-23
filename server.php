<?php
/**
 * IPAuditor - Server PHP Script
 * Captures and logs visitor's public IP address
 * Stores data in JSON format with timestamp
 */

// Set headers
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

// Get the directory where this script is located
$script_dir = dirname(__FILE__);
$json_file = $script_dir . '/ips.json';

/**
 * Function: Get client's real public IP address
 * Checks multiple headers to find the real IP
 */
function getClientIP() {
    $ip = '';
    
    // Check for IP from Cloudflare
    if (!empty($_SERVER['HTTP_CF_CONNECTING_IP'])) {
        $ip = $_SERVER['HTTP_CF_CONNECTING_IP'];
    }
    // Check for IP from proxy
    elseif (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
        $ips = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR']);
        $ip = trim($ips[0]);
    }
    // Check for remote address
    elseif (!empty($_SERVER['REMOTE_ADDR'])) {
        $ip = $_SERVER['REMOTE_ADDR'];
    }
    // Fallback
    else {
        $ip = 'UNKNOWN';
    }
    
    return filter_var($ip, FILTER_VALIDATE_IP) ? $ip : 'INVALID_IP';
}

/**
 * Function: Get current timestamp in ISO 8601 format
 */
function getCurrentTimestamp() {
    $now = new DateTime('now', new DateTimeZone('UTC'));
    return $now->format('Y-m-d H:i:s');
}

/**
 * Function: Get user agent string
 */
function getUserAgent() {
    return isset($_SERVER['HTTP_USER_AGENT']) ? $_SERVER['HTTP_USER_AGENT'] : 'Unknown';
}

/**
 * Function: Initialize JSON file if it doesn't exist
 */
function initializeJsonFile($file_path) {
    if (!file_exists($file_path)) {
        file_put_contents($file_path, json_encode([], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
        chmod($file_path, 0666);
    }
}

/**
 * Function: Append IP data to JSON file
 */
function recordIPAddress($file_path, $ip, $timestamp, $user_agent) {
    // Initialize file if needed
    initializeJsonFile($file_path);
    
    // Read existing data
    $json_content = file_get_contents($file_path);
    $data = json_decode($json_content, true);
    
    // Ensure $data is an array
    if (!is_array($data)) {
        $data = [];
    }
    
    // Create new entry
    $entry = [
        'ip' => $ip,
        'timestamp' => $timestamp,
        'user_agent' => $user_agent
    ];
    
    // Append new entry
    $data[] = $entry;
    
    // Write updated data back to file
    $json_options = JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE;
    file_put_contents($file_path, json_encode($data, $json_options));
    
    return $entry;
}

/**
 * Main Logic
 */

// Get IP, timestamp, and user agent
$client_ip = getClientIP();
$timestamp = getCurrentTimestamp();
$user_agent = getUserAgent();

// Record the IP address
$entry = recordIPAddress($json_file, $client_ip, $timestamp, $user_agent);

// Log to server output for CLI display
error_log("[IPAuditor] New connection: IP=$client_ip at $timestamp");

// Prepare response
$response = [
    'status' => 'success',
    'message' => 'IP address recorded successfully',
    'data' => $entry
];

// Return JSON response
echo json_encode($response, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
?>
