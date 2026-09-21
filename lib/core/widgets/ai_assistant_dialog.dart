import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/resort.dart';
import '../models/user_profile.dart';
import '../services/mock_data_store.dart';
import '../theme/app_theme.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final Resort? actionResort;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.actionResort,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AIAssistantDialog extends StatefulWidget {
  const AIAssistantDialog({super.key});

  @override
  State<AIAssistantDialog> createState() => _AIAssistantDialogState();
}

class _AIAssistantDialogState extends State<AIAssistantDialog> {
  final MockDataStore _store = MockDataStore.instance;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _initWelcomeMessage();
  }

  void _initWelcomeMessage() {
    final user = _store.currentUser;
    final role = user?.role ?? AppRole.customer;

    String welcomeText = '';
    if (role == AppRole.superAdmin) {
      welcomeText = "👋 Hello Super Admin! I am Vickky, your Platform AI Analyst. Ask me about platform revenue, resort performance, active subscriptions, or co-owner metrics.";
    } else if (role == AppRole.admin) {
      final resortId = user?.resortId ?? 'resort-grand-palms';
      final resort = _store.resorts[resortId];
      welcomeText = "👋 Hello Manager! I am Vickky, your Ops Co-Pilot for ${resort?.name ?? 'your resort'}. Ask me about occupancy rates, month revenue, or staff task allocations.";
    } else {
      welcomeText = "👋 Hi there! I'm Vickky, your ResortHub Assistant. Tell me where you want to travel, your budget in ₹, or what kind of resort experience you're looking for!";
    }

    _messages.add(ChatMessage(text: welcomeText, isUser: false));
  }

  List<String> _getQuickPrompts() {
    final user = _store.currentUser;
    final role = user?.role ?? AppRole.customer;

    if (role == AppRole.superAdmin) {
      return [
        "📊 Platform revenue summary",
        "🏖️ Highest rated resorts",
        "👑 Active subscription tiers",
        "➕ How to onboard new resort",
      ];
    } else if (role == AppRole.admin) {
      return [
        "📈 Current occupancy rate",
        "💰 Month revenue breakdown",
        "🛠️ Manage Incharge & Ops",
        "🏨 Recommend room pricing",
      ];
    } else {
      return [
        "🏖️ Beachfront resorts in Goa",
        "🏔️ Hill stations under ₹15,000",
        "⭐ Top rated luxury stays",
        "📅 Date blocking & cancellation policy",
      ];
    }
  }

  void _handleSubmitted(String text) {
    if (text.trim().isEmpty) return;

    final query = text.trim();
    _inputController.clear();

    setState(() {
      _messages.add(ChatMessage(text: query, isUser: true));
    });

    _scrollToBottom();

    // Generate AI response
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final aiResponse = _generateResponse(query);
      setState(() {
        _messages.add(aiResponse);
      });
      _scrollToBottom();
    });
  }

  ChatMessage _generateResponse(String query) {
    final q = query.toLowerCase();
    final user = _store.currentUser;
    final role = user?.role ?? AppRole.customer;
    final resorts = _store.resorts.values.toList();

    // 1. Role Specific Queries: Super Admin
    if (role == AppRole.superAdmin) {
      if (q.contains('revenue') || q.contains('platform') || q.contains('summary')) {
        final activeSubs = _store.resortSubscriptions.values.where((s) => s.status.name == 'active').length;
        return ChatMessage(
          text: "📊 **Platform Executive Summary**:\n\n"
              "• Total Registered Resorts: ${resorts.length}\n"
              "• Active Subscriptions: $activeSubs\n"
              "• Total Platform Monthly Revenue: **₹21.4K**\n\n"
              "All resorts are currently operating with assigned admins!",
          isUser: false,
        );
      }
      if (q.contains('subscription') || q.contains('tier')) {
        return ChatMessage(
          text: "👑 **Subscription Tiers Overview**:\n\n"
              "• Premium Tiers: Grand Hyatt Goa, Taj Lake Palace\n"
              "• Standard Tiers: Blanket Hotel Munnar, Kumarakom Lake Resort\n"
              "• Basic Tiers: Wildflower Hall Shimla\n\n"
              "You can manage tier upgrades in the Subscriptions Portal.",
          isUser: false,
        );
      }
    }

    // 2. Role Specific Queries: Resort Admin
    if (role == AppRole.admin) {
      final resortId = user?.resortId ?? 'resort-grand-palms';
      final report = _store.getDashboardReport(resortId);
      final resort = _store.resorts[resortId];

      if (q.contains('occupancy') || q.contains('revenue') || q.contains('rate')) {
        return ChatMessage(
          text: "📈 **Ops Insight for ${resort?.name}**:\n\n"
              "• Month Revenue: **₹${report.monthRevenue.toStringAsFixed(2)}**\n"
              "• Occupancy Rate: **${report.occupancyRate}%**\n"
              "• Upcoming Check-ins: **${report.upcomingArrivals}**\n\n"
              "💡 *AI Tip*: Weekend demand is high! Consider maintaining current premium rates.",
          isUser: false,
        );
      }
    }

    // 3. Customer Queries & General Searches
    if (q.contains('goa') || q.contains('beach')) {
      final goaResort = resorts.firstWhere(
        (r) => r.city.toLowerCase().contains('goa') || r.description.toLowerCase().contains('beach'),
        orElse: () => resorts.first,
      );
      final units = _store.resortUnits[goaResort.id] ?? [];
      final price = units.isNotEmpty ? units.first.pricePerNight : 12000.0;

      return ChatMessage(
        text: "🏖️ **Top Beachfront Recommendation**: **${goaResort.name}**\n\n"
            "📍 Location: ${goaResort.city}, ${goaResort.state}\n"
            "⭐ Rating: ${goaResort.rating} (${goaResort.rating >= 4.8 ? 'Superb' : 'Fabulous'})\n"
            "💵 Price: **₹${price.toStringAsFixed(0)}** per night (+ taxes)\n"
            "✓ Features: Infinity pool, beachfront view, free cancellation.",
        isUser: false,
        actionResort: goaResort,
      );
    }

    if (q.contains('munnar') || q.contains('shimla') || q.contains('hill') || q.contains('mountain')) {
      final hillResort = resorts.firstWhere(
        (r) => r.city.toLowerCase().contains('munnar') || r.city.toLowerCase().contains('shimla'),
        orElse: () => resorts.length > 2 ? resorts[2] : resorts.first,
      );
      final units = _store.resortUnits[hillResort.id] ?? [];
      final price = units.isNotEmpty ? units.first.pricePerNight : 8500.0;

      return ChatMessage(
        text: "🏔️ **Top Hill Station Retreat**: **${hillResort.name}**\n\n"
            "📍 Location: ${hillResort.city}, ${hillResort.state}\n"
            "⭐ Rating: ${hillResort.rating}\n"
            "💵 Price: **₹${price.toStringAsFixed(0)}** per night\n"
            "✓ Features: Mountain view tea gardens, bonfire, spa.",
        isUser: false,
        actionResort: hillResort,
      );
    }

    if (q.contains('cancellation') || q.contains('policy') || q.contains('block') || q.contains('date')) {
      return ChatMessage(
        text: "📅 **ResortHub Booking Policies**:\n\n"
            "1. **Date Overlap Protection**: Reserved dates are automatically blocked for other customers to prevent double-booking.\n"
            "2. **Free Cancellation**: Cancel up to 48 hours before check-in for full advance refund.\n"
            "3. **Currency**: All amounts and invoices rendered in **Rupees (₹)**.",
        isUser: false,
      );
    }

    if (q.contains('cheap') || q.contains('budget') || q.contains('under') || q.contains('price')) {
      return ChatMessage(
        text: "💰 **Budget-Friendly Stay Options**:\n\n"
            "• **Wildflower Hall Shimla**: Starts from **₹7,500/night**\n"
            "• **Blanket Hotel Munnar**: Starts from **₹8,500/night**\n"
            "• **Grand Hyatt Goa**: Starts from **₹12,000/night**\n\n"
            "All stays include free Wi-Fi and complimentary breakfast!",
        isUser: false,
      );
    }

    // Default Fallback Search
    final matchingResort = resorts.firstWhere(
      (r) => r.name.toLowerCase().contains(q) || r.city.toLowerCase().contains(q),
      orElse: () => resorts.first,
    );

    return ChatMessage(
      text: "🤖 Here is what I found for **$query**:\n\n"
          "**${matchingResort.name}** in ${matchingResort.city}, ${matchingResort.state}.\n"
          "Rating: ⭐ ${matchingResort.rating}\n"
          "Description: ${matchingResort.description}\n\n"
          "Would you like to view dates or see availability for this resort?",
      isUser: false,
      actionResort: matchingResort,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: AppTheme.bookingNavy,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppTheme.bookingYellow,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.smart_toy_outlined, color: AppTheme.bookingNavy, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vickky AI Assistant', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Instant Stay & Ops Guide', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Quick Prompts Chips
            Container(
              height: 44,
              color: Colors.grey.shade50,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _getQuickPrompts().map((prompt) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(prompt, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      backgroundColor: Colors.blue.shade50,
                      side: BorderSide(color: Colors.blue.shade200),
                      onPressed: () => _handleSubmitted(prompt),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),

            // Chat Messages List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  return _buildMessageBubble(msg);
                },
              ),
            ),

            // Input Text Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(
                        hintText: 'Ask about resorts, prices in ₹, or policies...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: _handleSubmitted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppTheme.bookingNavy,
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: AppTheme.bookingYellow, size: 18),
                      onPressed: () => _handleSubmitted(_inputController.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: AppTheme.bookingNavy,
              child: const Icon(Icons.smart_toy, color: AppTheme.bookingYellow, size: 14),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.bookingNavy : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14).copyWith(
                  bottomRight: isUser ? const Radius.circular(2) : const Radius.circular(14),
                  bottomLeft: !isUser ? const Radius.circular(2) : const Radius.circular(14),
                ),
                border: !isUser ? Border.all(color: Colors.grey.shade300) : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (msg.actionResort != null) ...[
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.hotel, size: 14),
                      label: Text('View ${msg.actionResort!.name}', style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.bookingActionBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.go('/customer/resort/${msg.actionResort!.id}');
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: AppTheme.bookingYellow,
              child: const Icon(Icons.person, color: AppTheme.bookingNavy, size: 14),
            ),
          ],
        ],
      ),
    );
  }
}

class AIAssistantFAB extends StatelessWidget {
  const AIAssistantFAB({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'ai_assistant_fab_${context.hashCode}',
      backgroundColor: AppTheme.bookingNavy,
      foregroundColor: AppTheme.bookingYellow,
      tooltip: 'Vickky AI Assistant',
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => const AIAssistantDialog(),
        );
      },
      child: const Icon(Icons.smart_toy_outlined, size: 26),
    );
  }
}
