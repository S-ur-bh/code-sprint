import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:postgres/postgres.dart';

void main() {
  runApp(const MyApp());
}

// Keep the CodeForcesUser class as is
class CodeForcesUser {
  final String handle;
  final String firstName;
  final String lastName;
  final int rating;
  final String rank;
  final String avatar;
  final String titlePhoto;

  CodeForcesUser({
    required this.handle,
    required this.firstName,
    required this.lastName,
    required this.rating,
    required this.rank,
    required this.avatar,
    required this.titlePhoto,
  });

  factory CodeForcesUser.fromJson(Map<String, dynamic> json) {
    return CodeForcesUser(
      handle: json['handle'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      rating: json['rating'] ?? 0,
      rank: json['rank'] ?? '',
      avatar: json['avatar'] ?? '',
      titlePhoto: json['titlePhoto'] ?? '',
    );
  }
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Codeforces User Info',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const UserInfoPage(),
    );
  }
}

class UserInfoPage extends StatefulWidget {
  const UserInfoPage({super.key});

  @override
  _UserInfoPageState createState() => _UserInfoPageState();
}

class _UserInfoPageState extends State<UserInfoPage> {
  List<CodeForcesUser> _users = [];
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
  }

  Future<void> _fetchUserInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.get(Uri.parse(
          'https://codeforces.com/api/user.info?handles=DmitriyH;Fefer_Ivan&checkHistoricHandles=false'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);

        if (data['status'] == 'OK') {
          final users = (data['result'] as List)
              .map((userData) => CodeForcesUser.fromJson(userData))
              .toList();

          setState(() {
            _users = users;
          });

          // Store data in Neon PostgreSQL
          await _storeUsersInDatabase(users);
        } else {
          setState(() {
            _errorMessage = 'Failed to fetch user data';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'HTTP Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
      print('Error fetching user info: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _storeUsersInDatabase(List<CodeForcesUser> users) async {
    PostgreSQLConnection? connection;
    try {
      connection = PostgreSQLConnection(
        'ep-sweet-glade-a8qajugr.eastus2.azure.neon.tech',
        5432,
        'neondb',
        username: 'neondb_owner',
        password: 'Fwz3Nsqg5rTb',
        useSSL: true, // Ensure SSL connection
      );

      await connection.open();

      for (var user in users) {
        try {
          // Check if user already exists to avoid duplicates
          final existingUser = await connection.query(
            'SELECT * FROM codeforces_users WHERE handle = @handle',
            substitutionValues: {'handle': user.handle},
          );

          if (existingUser.isEmpty) {
            await connection.query(
              'INSERT INTO codeforces_users (handle, first_name, last_name, rating, rank, avatar, title_photo) VALUES (@handle, @firstName, @lastName, @rating, @rank, @avatar, @titlePhoto)',
              substitutionValues: {
                'handle': user.handle,
                'firstName': user.firstName,
                'lastName': user.lastName,
                'rating': user.rating,
                'rank': user.rank,
                'avatar': user.avatar,
                'titlePhoto': user.titlePhoto,
              },
            );
            print('User ${user.handle} inserted successfully');
          } else {
            print('User ${user.handle} already exists');
          }
        } catch (insertError) {
          print('Error inserting user ${user.handle}: $insertError');
        }
      }
    } catch (e) {
      print('Database connection error: $e');
      setState(() {
        _errorMessage = 'Database error: $e';
      });
    } finally {
      await connection?.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Codeforces Users'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Error',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              _errorMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            ElevatedButton(
              onPressed: _fetchUserInfo,
              child: const Text('Retry'),
            )
          ],
        ),
      )
          : ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundImage: NetworkImage(user.avatar),
            ),
            title: Text('${user.firstName} ${user.lastName}'),
            subtitle: Text('Handle: ${user.handle}, Rating: ${user.rating}'),
          );
        },
      ),
    );
  }
}

