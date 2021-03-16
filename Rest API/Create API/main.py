from flask import Flask, request, jsonify, make_response    #note that "request" is not your usual python request library, it is specially customized for flask.
from flask_sqlalchemy import SQLAlchemy
import uuid
from werkzeug.security import generate_password_hash, check_password_hash
import jwt
import datetime
from functools import wraps

app = Flask(__name__)

#these are not simple values, the keys are pre-defined which will be used automatically during execution. Its like setting pre-requisites and everything will be handled in backend by flask and alchemy.
app.config['SECRET_KEY'] = 'thisissecret'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///todo.db'

######## DATABASE ########

#create database
db = SQLAlchemy(app)


#Define database tables
class Users(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(50), unique=True)   # for get_one_user() , to make things less predictable on public facing and prevent idors.
    name = db.Column(db.String(50))
    password = db.Column(db.String(80))
    admin = db.Column(db.Boolean)


class Todo(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    text = db.Column(db.String(50))
    complete = db.Column(db.Boolean)
    user_id = db.Column(db.Integer)

#python decorators are used to modify function execution without changing the original function defination. To do so we create a new fuction, pass our original function to it, do processing and return the modified function's output.
def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None

        if 'x-access-token' in request.headers:
            token = request.headers['x-access-token']

        if not token:
            return jsonify({"message": "Token is missing !"}), 401

        try:
            print(app.config['SECRET_KEY'])
            print(token)
            data = jwt.decode(token, app.config['SECRET_KEY'], algorithms=["HS256"])
            print(data)
            print("reached here also!")
            current_user = Users.query.filter_by(public_id=data['public_id']).first()
        except Exception as e:
            print(e)
            return jsonify({"message": "Damm Token is invalid!"}), 401

        #if reached here then it means the user has token and is authorized
        return f(current_user, *args, **kwargs) #due to this we need to add current_user as our first argument for all our routes.
    return decorated    #this line calls the function

####### FLASK ROUTES ########
@app.route('/user', methods=['POST'])   #original function
@token_required   #modified function, now only modified function will be executed
def create_user(current_user):
    data = request.get_json()

    hashed_password = generate_password_hash(data['password'], method='sha256')

    #define procedure to create a "User" with define parameters. Procedure = a prepared statement or where we have defined all the values, the only thing that is left is to execute it.
    new_user = Users(public_id=str(uuid.uuid4()), name=data['name'], password=hashed_password, admin=False)

    #queue it in session.
    db.session.add(new_user)

    #execute the session tasks.
    db.session.commit()

    return jsonify({'message': 'new user created'})


@app.route('/user', methods=['GET'])
@token_required
def get_all_users(current_user):

    #only admins are allowed to use this.
    if not current_user.admin:
        return jsonify({"message": "You cannot perform the function! You need to be admin!"})

    #query user's table to get the complete table
    users = Users.query.all()

    output = []

    #convert each user row into a proper data structure i.e. json and adding all these rows to final "output"
    for user in users:
        user_data = {}
        user_data['public_id'] = user.public_id
        user_data['name'] = user.name
        user_data['password'] = user.password
        user_data['admin'] = user.admin
        output.append(user_data)

    return jsonify({"users": output})


@app.route('/user/<public_id_user>', methods=['GET'])
@token_required
def get_one_user(current_user, public_id_user):
    user = Users.query.filter_by(public_id=public_id_user).first()

    if user == None:
        return jsonify({"message": "No bro wrong user given"})

    output = {}

    output['public_id'] = user.public_id
    output['admin'] = user.admin
    output['password'] = user.password
    output['name'] = user.name

    return jsonify(output)


@app.route('/user/<public_id_user>', methods=['PUT'])              #promote normal user to admin user.
@token_required
def promote_user(current_user, public_id_user):

    #only admins are allowed to use this.
    if not current_user.admin:
        return jsonify({"message": "You cannot perform the function! You need to be admin!"})

    user = Users.query.filter_by(public_id=public_id_user).first()

    if user == None:
        return jsonify({"message": "No bro wrong user given"})

    user.admin = True

    db.session.commit()

    return jsonify({"Message": "User has been promoted."})


@app.route('/user/<public_id_user>', methods=['DELETE'])
@token_required
def delete_user(current_user, public_id_user):

    #only admins are allowed to use this.
    if not current_user.admin:
        return jsonify({"message": "You cannot perform the function! You need to be admin!"})

    user = Users.query.filter_by(public_id=public_id_user).first()

    if user == None:
        return jsonify({"message": "No bro user is not there!"})

    db.session.delete(user)

    db.session.commit()


    return jsonify({"message": "user has been deleted"})


@app.route('/login', methods=['POST'])      #using HTTP basic authenticiation
def login():

    auth = request.authorization

    print(auth)

    if not auth or not auth.username or not auth.password:
        return make_response("Please provide credentials properly", 401, {"Authenticate": "Basic realm='Login Required!'"})
        # return jsonify({"message": "The data does not match our database"}), 401

    user = Users.query.filter_by(name=auth.username).first()

    print(user)

    if not user:
        return make_response("The user is not present in the database", 401, {"Authenticate": "Basic realm='Login Required!'"})

    print(auth.password)
    # print(user.password)
    #if reached here then user exists in the database
    if check_password_hash(user.password, auth.password):   #auth.password = clear text password, user.password= hashed password
        #create the authorization
        #first argument is data to encode
        #using datetime to set the expiration date (Unix UTC timestamp) and timedelta is amount of time the token is valid = 30 minutes
        #app.config["SECRET_KEY"] key is used to encode jwt.encode()
        token = jwt.encode({"public_id": user.public_id, "exp": datetime.datetime.utcnow() + datetime.timedelta(minutes=30)}, app.config['SECRET_KEY'], algorithm="HS256")

        return jsonify({"token": token})

    #user is present but invalid password
    return make_response("User is present but Invalid credentials", 401, {"Authenticate": "Basic realm='Login Required!'"})

if __name__ == "__main__":
    app.run(debug=True)
