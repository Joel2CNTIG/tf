require 'sinatra'
require 'sinatra/reloader'
require 'slim'
require 'sqlite3'
require 'bcrypt'

enable :sessions 

module Model

  # Calculates the average of all integers in an array
  #
  # @arr [Array] array of integer
  #
  # @return [Float] average of integers in array
  def average(arr)
    return arr.sum/arr.size
  end

  # Times out the user if it detects them logging in too fast
  #
  # @time_arr [Array] array of times
  #
  # @return [Array] An array of information gathered from the method
  def timeout(time_arr)
    time_arr = time_arr.last(5)
    if time_arr.length == 5
      time_intervals = []
      compared_time = time_arr[0]
      time_arr.each do |time|
        new_time = time - compared_time
        time_intervals << new_time
      end
      if average(time_intervals) <= 10
        status = "toofast"
        cooldown = true
        time1 = Time.now
        redirect = '/login'
      end
    end
    return [status, cooldown, time1, redirect]
  end

  # Creates database based on given path
  #
  # @path [String] path containing .db file
  # 
  # @return [Database] A database based on a .db file refered to in the path

  def connect_db(path)
    return SQLite3::Database.new(path)
  end

  # Checks permissions for entering routes
  #
  # @db [Database] database
  # @cooldown [Boolean] signifies whether site is under cooldown
  # @time1 [Time] time when cooldown occured
  # @id [Integer] user id
  # @tag [String] tag to signify user authority
  # @time_arr [Array] array of times for cooldown
  # @status [String] user to signify errors
  # @username [String] username
  # @password [String] password
  #
  # @return [Array] Array of data for app to process into sessions
  def before_all(db, cooldown, time1, id, tag, time_arr, status, username, password)
    if cooldown == true
      time2 = Time.now
      if time2 - time1 > 5
        cooldown = false 
        time1 = nil
        status = nil
        time_arr = nil
      else
        unless request.path_info.include?('/cooldown')
          return [cooldown, status, time_arr, username, password, "/../cooldown"]
        end
      end
    end
    restricted_routes = ['/create']
    login_routes = ['/', '/login', '/post-login', '/post-register', '/post-guest', '/wrong_username_or_pwd', '/username_too_long', '/username_already_exists', '/post-too_long', '/cooldown']
    if id == nil && !login_routes.include?(request.path_info) && tag != "guest"
      tag = nil
      username = nil
      password = nil
      status = nil 
      redirect = '/'
    end
    if !login_routes.include?(request.path_info) && tag != "guest" && username != db.execute("SELECT username FROM user WHERE id = ?", id).first["username"]
      tag = nil
      username = nil
      password = nil
      status = nil 
      redirect = '/'
    end
    if tag == "guest" && restricted_routes.include?(request.path_info)
      redirect = '/home'
    end
    if tag != "admin" && request.path_info.include?('/admin')
      redirect = '/home'
    end
    if tag == nil && !login_routes.include?(request.path_info)
      redirect = '/'
    end
    return[cooldown, status, time_arr, username, password, redirect]
  end

  # Attemps to log in user
  # @See timeout
  #
  # @db [Database] database
  # @username [String] username
  # @password [String] password
  # @time_arr [Array] array of times, used for cooldown
  #
  # @return [Array] Array of login data
  def post_login(db, username, password, time_arr)
    time_arr << Time.now
    timeout = timeout(time_arr)
    if timeout[0] == "toofast"
      return timeout
    end
    result = db.execute("SELECT password FROM user WHERE username = ?",username).first
    if result != nil && BCrypt::Password.new(result["password"]) == password
      id = db.execute("SELECT id FROM user WHERE username = ?",username).first["id"]
      if username == "admin" 
        return ["admin", id]
      else
        return ["user", id]
      end
    else
      return ["wrong_user_or_pwd"]
    end
  end
    
  # Attemps to register user
  #
  # @db [Database] database
  # @username [String] username
  # @password [String] password
  # @password_again [String] password_again
  #
  # @return [Array] Array of register data
  def post_register(db, username, password, password_again)
    compared_username = db.execute("SELECT username FROM user WHERE username LIKE ?",username).first
    password_digest = BCrypt::Password.create(password)
    if username.length > 20
      return ["toolong", '/', nil, nil, nil, nil]
    end
    if username == "" || password == "" 
      return ["emptyfields", '/', nil, nil, nil, nil]
    end
    forbidden_chars = [" ", ",", ":", ";", "?", "!", "]", "[", "&", "=", "}", "{", "%", "¤", "$", "#", "£", "'", "@", "ä", "å", "ö", "|", "<", ">"]
    forbidden_chars.each do |char|
      if username.include?(char)
        return ["forbiddenchar", '/', nil, nil, nil, nil]
      end
    end
    if password_again == password
      if compared_username == nil 
        db.execute("INSERT INTO user (username, password) VALUES (?,?)",username, password_digest)
        if username == "admin" 
          tag = "admin"
        else
          tag = "user"
        end
        id = db.execute("SELECT id FROM user WHERE username = ?",username).first["id"]
        return [nil, '/home', username, password, id, tag]
      else
        return ["alreadyexists", '/', nil, nil, nil, nil]
      end
    else
      return ["nomatch", '/', nil, nil, nil, nil]
    end
  end

  # Attemps to create post
  #
  # @db [Database] database
  # @id [Integer] post id
  # @title [String] post title
  # @description [String] post description
  # @price [Integer] post price
  # @keyword [String] keyword 1
  # @keyword2 [String] keyword 2
  # @keyword2 [String] keyword 3
  #
  # @return [Arr] Array of status and redirect
  def post_create(db, id, title, description, price, keyword, keyword2, keyword3)
    if title == "" || description == "" || price == ""
      return ["create_error", '/create']
    end
    keywords = []
    unless keyword == nil || keyword == ""
      keywords << keyword
    end
    unless keyword2 == nil || keyword2 == ""
      keywords << keyword2
    end
    unless keyword3 == nil || keyword3 == ""
      keywords << keyword3
    end
    db.execute("INSERT INTO projects (user_id, title, description, visits, price) VALUES (?,?,?,?,?)", id, title, description, 0, price)
    proj_id = db.execute("SELECT id FROM projects WHERE title = ?", title).first["id"]
    keywords.each do |word|
      key_id = db.execute("SELECT id FROM keywords WHERE word = ?", word).first["id"]
      db.execute("INSERT INTO project_keyword_relationship (project_id, keyword_id) VALUES (?,?)", proj_id, key_id)
    end
    return [nil, '/home']
  end

  # Attempts to edit post
  #
  # @db [Database] database
  # @id [Integer] post id
  # @title [String] post title
  # @description [String] post description
  # @price [Integer] post price
  # @keyword1 [String] keyword 1
  # @keyword2 [String] keyword 2
  # @keyword2 [String] keyword 3
  #
  # @return [nil] No return, redirects and alters database when conditions are met
  def post_edit(db, id, title, description, price, keyword1, keyword2, keyword3)
    keywords = []
    unless keyword1 == nil || keyword1 == ""
      keywords << keyword1
    end
    unless keyword2 == nil || keyword2 == ""
      keywords << keyword2
    end
    unless keyword3 == nil || keyword3 == ""
      keywords << keyword3
    end
    unless title == ""
      db.execute("UPDATE projects SET title = ? WHERE id = #{id}", title)
    end
    unless description == ""
      db.execute("UPDATE projects SET description = ? WHERE id = #{id}", description)
    end
    unless price == ""
      db.execute("UPDATE projects SET price = ? WHERE id = #{id}", price)
    end
    keywords.each do |word|
      key_id = db.execute("SELECT id FROM keywords WHERE word = ?", word).first["id"]
      db.execute("INSERT INTO project_keyword_relationship (project_id, keyword_id) VALUES (?,?)", id, key_id)
    end
    redirect("/project/#{id}")
  end

  # Attempts to change password (settings)
  #
  # @db [Database] database
  # @id [Integer] user id
  # @pwd [String] new password
  # @old_pwd [String] old password
  # @pwd_again [String] password input again
  #
  # @return [Array] Array of data
  def post_settings_change_password(db, id, pwd, old_pwd, pwd_again)
    compared_old_pwd = db.execute("SELECT password FROM user WHERE id = ?", id).first["password"]
    if BCrypt::Password.new(compared_old_pwd) == old_pwd
      if pwd == pwd_again
        password_digest = BCrypt::Password.create(pwd)
        db.execute("UPDATE user SET password = ? WHERE id = ?", password_digest, id)
        return ["changedpwd", pwd, "settings/#{id}"]
      else
        return ["nomatch", nil, "/settings/#{id}/change_password"]
      end
    else
      return ["wrongpwd", nil, "/settings/#{id}/change_password"]
    end
  end

  # Attempts to change username (settings)
  #
  # @db [Database] database
  # @id [Integer] user id
  # @username [String] username
  # @tag [String] tag for authorization
  # 
  # @return [Array] Array of session and redirect info
  def post_settings_change_username(db, id, username, tag)
    all_usernames = db.execute("SELECT username FROM user")
    all_usernames.each do |name|
      name = name["username"]
      if username == name
        return ["alreadyexists", "/settings/#{id}/change_username", nil]
      end
    end
    unless tag == "admin" 
      db.execute("UPDATE user SET username = ? WHERE id = #{id}", username)
    end
    return [nil, "settings/#{id}", username]
    redirect("/settings/#{id}")
  end

  # Attempts to delete account (settings)
  #
  # @db [Database] database
  # @id [Integer] user id
  # @username [String] username
  # @password [String] password
  # @tag [String] tag for authorization
  #
  # @return [Boolean] to determine whether to clear sessions
  def post_settings_delete_account(db, id, username, password, tag)
    compared_username = db.execute("SELECT username FROM user WHERE id = ?", id).first["username"]
    compared_password = db.execute("SELECT password FROM user WHERE id = ?", id).first["password"]
    if username == compared_username && BCrypt::Password.new(compared_password) == password && tag != "admin"
      project_ids = db.execute("SELECT id FROM projects WHERE user_id = ?", id)
      project_ids.each do |projid|
        new_project_id = projid["id"]
        db.execute("DELETE FROM projects WHERE id = ?", new_project_id)
        db.execute("DELETE FROM project_keyword_relationship WHERE project_id = ?", new_project_id)
      end
      db.execute("DELETE FROM user WHERE id = ?", id)
      return true
      redirect('/')
    else
      redirect("settings/#{id}/delete_account")
    end
    return false
  end

  # Attempts to delete account (settings)
  #
  # @db [Database] database
  # @id [Integer] user id
  #
  # @return [nil] No return, redirects and alters database when conditions are met
  def post_admin_delete_account(db, id)
    if id == "1"
      redirect('/admin')
    end
    project_ids = db.execute("SELECT id FROM projects WHERE user_id = ?", id)
    project_ids.each do |projid|
      project_id = projid["id"]
      db.execute("DELETE FROM project_keyword_relationship WHERE project_id = ?", project_id)
    end
    db.execute("DELETE FROM projects WHERE user_id = ?", id)
    db.execute("DELETE FROM user WHERE id = ?", id)
    redirect('/../admin/manage_accounts')
  end

  # Convers array of ids for keywords into array of post titles where the posts contain said keywords
  #
  # @arr [Array] array of ids
  #
  # @return [Array] array of strings
  def keyid_array_to_title_array(arr)
    projid_array = []
    arr.each do |id|
      projid_array << @db.execute("SELECT project_id FROM project_keyword_relationship WHERE keyword_id = ?", id) 
    end
    titles = []
    projid_array.each do |idarray|
      idarray.each do |id|
        titles << @db.execute("SELECT title FROM projects WHERE id = ?", id["project_id"]).first
      end
    end
    return titles
  end

  # Attempts redirects to search path with searched for keywords' ids in params
  #
  # @db [Database] database
  # @keyword1 [String] keyword 1
  # @keyword2 [String] keyword 2
  # @keyword3 [String] keyword 3
  #
  # @return [nil] No return, redirects when conditions are met
  def post_search(db, keyword1, keyword2, keyword3)
    if keyword1 == ""
      key1 = "none"
    else
      key1 = db.execute("SELECT id FROM keywords WHERE word = ?", keyword1).first["id"]
    end
    if keyword2 == ""
      key2 = "none"
    else
      key2 = db.execute("SELECT id FROM keywords WHERE word = ?", keyword2).first["id"]
    end
    if keyword3 == ""
      key3 = "none"
    else
      key3 = db.execute("SELECT id FROM keywords WHERE word = ?", keyword3).first["id"]
    end
    redirect("/home/search/#{key1}/#{key2}/#{key3}")
  end
end