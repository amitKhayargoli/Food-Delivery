import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../widgets/step_progress_indicator.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

/// Full-screen form for creating or editing a menu item, divided into 3 steps.
///
/// Step 1 — Basic Info: name, description, base price, category
/// Step 2 — Media & Sizes: photos (min 3), size variants
/// Step 3 — Nutrition & Details: calories, portion weight, ingredients,
///          allergens, prep time, availability toggle
class AddEditMenuItemScreen extends StatefulWidget {
  final Food? existingItem;

  const AddEditMenuItemScreen({super.key, this.existingItem});

  bool get isEditing => existingItem != null;

  @override
  State<AddEditMenuItemScreen> createState() => _AddEditMenuItemScreenState();
}

class _AddEditMenuItemScreenState extends State<AddEditMenuItemScreen> {
  int _currentStep = 0;

  // ── Text controllers ──────────────────────────
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _caloriesCtrl = TextEditingController();
  final _portionWeightCtrl = TextEditingController();
  final _prepTimeCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();

  // ── Lists ─────────────────────────────────────
  final List<FoodSize> _sizes = [];
  final List<String> _imageUrls = [];
  final List<String> _ingredients = [];
  final List<String> _allergens = [];
  final List<File> _pendingImageFiles = [];

  bool _isAvailable = true;
  bool _isSaving = false;

  // Ingredient/allergen input controllers
  final _ingredientCtrl = TextEditingController();
  final _allergenCtrl = TextEditingController();

  // Size editing state
  final _sizeNameCtrl = TextEditingController();
  final _sizeWeightCtrl = TextEditingController();
  final _sizePriceCtrl = TextEditingController();
  bool _sizeIsPopular = false;
  int? _editingSizeIndex;

  // Step 1 field-level error state
  String? _nameError;
  String? _priceError;
  String? _categoryError;

  static const List<String> _categoryOptions = [
    'Burger',
    'Pizza',
    'Momo',
    'Sushi',
    'Dessert',
    'Nepali',
    'Indian',
    'Chinese',
    'Italian',
    'Mexican',
    'Thai',
    'Beverages',
    'Breakfast',
    'Salad',
    'Soup',
    'Other',
  ];

  // Step labels used by the progress indicator
  static const List<StepInfo> _steps = [
    StepInfo(number: '1', label: 'Basic Info'),
    StepInfo(number: '2', label: 'Media & Sizes'),
    StepInfo(number: '3', label: 'Nutrition'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existingItem != null) {
      _populateForm(widget.existingItem!);
    }
  }

  void _populateForm(Food item) {
    _nameCtrl.text = item.name;
    _descriptionCtrl.text = item.description;
    _priceCtrl.text = item.price.toStringAsFixed(0);
    _categoryCtrl.text = item.categoryId;
    _isAvailable = item.isAvailable;
    _sizes.addAll(item.sizes);
    _imageUrls.addAll(item.imageUrls);
    if (item.calories != null) _caloriesCtrl.text = item.calories.toString();
    if (item.portionWeight != null) _portionWeightCtrl.text = item.portionWeight!;
    if (item.prepTime != null) _prepTimeCtrl.text = item.prepTime.toString();
    if (item.ingredients != null) _ingredients.addAll(item.ingredients!);
    if (item.allergens != null) _allergens.addAll(item.allergens!);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _priceCtrl.dispose();
    _caloriesCtrl.dispose();
    _portionWeightCtrl.dispose();
    _prepTimeCtrl.dispose();
    _categoryCtrl.dispose();
    _ingredientCtrl.dispose();
    _allergenCtrl.dispose();
    _sizeNameCtrl.dispose();
    _sizeWeightCtrl.dispose();
    _sizePriceCtrl.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  // ── Step navigation with validation ──────────

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        setState(() {
          _nameError =
              _nameCtrl.text.trim().isEmpty ? 'Item name is required.' : null;
          final price = double.tryParse(_priceCtrl.text.trim());
          _priceError =
              price == null ? 'Enter a valid base price.' : null;
          _categoryError = _categoryCtrl.text.trim().isEmpty
              ? 'Please select a category.'
              : null;
        });
        return _nameError == null && _priceError == null && _categoryError == null;

      case 1:
        // Check minimum 3 photos
        final totalImages = _imageUrls.length + _pendingImageFiles.length;
        if (totalImages < 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Please upload at least 3 photos (${3 - totalImages} more needed).'),
              backgroundColor: const Color(0xFFF57C00),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return false;
        }
        return true;

      case 2:
        return true;

      default:
        return true;
    }
  }

  void _goToStep(int step) {
    if (step < 0 || step > 2) return;
    if (step > _currentStep && !_validateStep(_currentStep)) return;
    setState(() => _currentStep = step);
  }

  // ── Image picking ────────────────────────────

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final file in result.files) {
        if (file.path != null) {
          _pendingImageFiles.add(File(file.path!));
        }
      }
    });
  }

  Future<void> _uploadPendingImages() async {
    final token = _token;
    if (token == null || _pendingImageFiles.isEmpty) return;

    final storage = di.sl<StorageService>();

    for (final file in _pendingImageFiles) {
      try {
        final url = await storage.uploadFoodImage(
          filePath: file.path,
          token: token,
        );
        _imageUrls.add(url);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload ${file.path.split('/').last}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
    _pendingImageFiles.clear();
  }

  // ── Size management ──────────────────────────

  void _addSize() {
    final name = _sizeNameCtrl.text.trim();
    final weight = _sizeWeightCtrl.text.trim();
    final price = double.tryParse(_sizePriceCtrl.text.trim());

    if (name.isEmpty || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Size name and price are required.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      if (_editingSizeIndex != null) {
        _sizes[_editingSizeIndex!] = FoodSize(
          name: name,
          weight: weight,
          price: price,
          isPopular: _sizeIsPopular,
        );
        _editingSizeIndex = null;
      } else {
        _sizes.add(FoodSize(
          name: name,
          weight: weight,
          price: price,
          isPopular: _sizeIsPopular,
        ));
      }
      _sizeNameCtrl.clear();
      _sizeWeightCtrl.clear();
      _sizePriceCtrl.clear();
      _sizeIsPopular = false;
    });
  }

  void _editSize(int index) {
    final size = _sizes[index];
    _sizeNameCtrl.text = size.name;
    _sizeWeightCtrl.text = size.weight;
    _sizePriceCtrl.text = size.price.toStringAsFixed(0);
    _sizeIsPopular = size.isPopular;
    _editingSizeIndex = index;
  }

  void _removeSize(int index) {
    setState(() {
      _sizes.removeAt(index);
      if (_editingSizeIndex == index) {
        _editingSizeIndex = null;
        _sizeNameCtrl.clear();
        _sizeWeightCtrl.clear();
        _sizePriceCtrl.clear();
        _sizeIsPopular = false;
      }
    });
  }

  // ── Ingredient / Allergen management ─────────

  void _addIngredient() {
    final text = _ingredientCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _ingredients.add(text);
        _ingredientCtrl.clear();
      });
    }
  }

  void _removeIngredient(int index) {
    setState(() => _ingredients.removeAt(index));
  }

  void _addAllergen() {
    final text = _allergenCtrl.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _allergens.add(text);
        _allergenCtrl.clear();
      });
    }
  }

  void _removeAllergen(int index) {
    setState(() => _allergens.removeAt(index));
  }

  // ── Save ─────────────────────────────────────

  Future<void> _save() async {
    // Validate all required fields one last time
    if (!_validateStep(0)) return;

    // Photo count already validated on step 2, but re-check
    final totalImages = _imageUrls.length + _pendingImageFiles.length;
    if (totalImages < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Please upload at least 3 photos (${3 - totalImages} more needed).'),
          backgroundColor: const Color(0xFFF57C00),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final token = _token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in first.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    // Upload pending images first
    await _uploadPendingImages();

    final data = {
      'name': _nameCtrl.text.trim(),
      'description': _descriptionCtrl.text.trim(),
      'base_price': double.tryParse(_priceCtrl.text.trim()) ?? 0,
      'category': _categoryCtrl.text.trim().isEmpty
          ? null
          : _categoryCtrl.text.trim(),
      'is_available': _isAvailable,
      'images': _imageUrls,
      'calories': int.tryParse(_caloriesCtrl.text.trim()),
      'portion_weight': _portionWeightCtrl.text.trim().isEmpty
          ? null
          : _portionWeightCtrl.text.trim(),
      'allergens': _allergens,
      'ingredients': _ingredients,
      'sizes': _sizes.map((s) => s.toJson()).toList(),
      'prep_time': int.tryParse(_prepTimeCtrl.text.trim()),
    };

    try {
      final api = di.sl<ApiService>();

      if (widget.isEditing) {
        await api.updateMenuItem(
          itemId: widget.existingItem!.id,
          data: data,
          token: token,
        );
      } else {
        await api.createMenuItem(data: data, token: token);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing
                ? 'Menu item updated!'
                : 'Menu item created!'),
            backgroundColor: const Color(0xFF52C41A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: _buildCurrentStep(),
              ),
            ),
            // Bottom action bar — shown only on step 0 (Continue) and step 3 (Save)
            if (_currentStep == 0 || _currentStep == 2)
              _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1BasicInfo();
      case 1:
        return _buildStep2MediaAndSizes();
      case 2:
        return _buildStep3NutritionAndDetails();
      default:
        return _buildStep1BasicInfo();
    }
  }

  // ──────────────────────────────────────────────
  //  Step 1 — Basic Info
  // ──────────────────────────────────────────────

  Widget _buildStep1BasicInfo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        // Header row: back button + icon
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x1A000000),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF1A1A1A),
                  size: 20,
                ),
              ),
            ),
            const Text(
              'Add Menu',
              style: TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                height: 1.33,
              ),
            ),
            const Spacer(),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 8),
        // Title
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Basic Information',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.33,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Step 1 of 3: Tell us what you\'re selling.',
            style: TextStyle(
              color: Color(0xFF595959),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Progress indicator
        const StepProgressIndicator(
          currentStep: 0,
          steps: _steps,
        ),
        const SizedBox(height: 24),
        // Form card
        _formCard([
          // Item Name
          _stepFieldLabel('Item Name *'),
          const SizedBox(height: 4),
          _buildStepTextField(
            controller: _nameCtrl,
            hint: 'e.g. Classic Smash Burger',
            errorText: _nameError,
            onChanged: (_) {
              if (_nameError != null) {
                setState(() => _nameError = null);
              }
            },
          ),
          const SizedBox(height: 20),
          // Description
          _stepFieldLabel('Description'),
          const SizedBox(height: 4),
          _buildStepTextField(
            controller: _descriptionCtrl,
            hint: 'Describe this item',
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          // Base Price
          _stepFieldLabel('Base Price (Rs) *'),
          const SizedBox(height: 4),
          _buildStepTextField(
            controller: _priceCtrl,
            hint: '350',
            keyboardType: TextInputType.number,
            errorText: _priceError,
            onChanged: (_) {
              if (_priceError != null) {
                setState(() => _priceError = null);
              }
            },
          ),
          const SizedBox(height: 20),
          // Category
          _stepFieldLabel('Category'),
          const SizedBox(height: 4),
          _buildCategoryDropdown(),
          if (_categoryError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _categoryError!,
                style: const TextStyle(
                  color: Color(0xFFF5222D),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _categoryError != null
            ? const Color(0xFFFFF1F0)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _categoryError != null
              ? const Color(0xFFF5222D)
              : const Color(0xFFE8E8E8),
          width: _categoryError != null ? 1.5 : 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _categoryCtrl.text.isNotEmpty &&
                  _categoryOptions.contains(_categoryCtrl.text)
              ? _categoryCtrl.text
              : null,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Color(0xFF1A1A1A),
            size: 22,
          ),
          hint: const Text(
            'Select category',
            style: TextStyle(
              color: Color(0xFFBFBFBF),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          items: _categoryOptions.map((cat) {
            return DropdownMenuItem(
              value: cat,
              child: Text(
                cat,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _categoryCtrl.text = v;
                _categoryError = null;
              });
            }
          },
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Step 2 — Media & Sizes
  // ──────────────────────────────────────────────

  Widget _buildStep2MediaAndSizes() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        // Header row: back button + icon
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x1A000000),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF1A1A1A),
                  size: 20,
                ),
              ),
            ),
            const Text(
              'Add Menu',
              style: TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                height: 1.33,
              ),
            ),
            const Spacer(),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 8),
        // Title
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Media & Sizes',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.33,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Step 2 of 3: Add photos and size variants.',
            style: TextStyle(
              color: Color(0xFF595959),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Progress indicator
        const StepProgressIndicator(
          currentStep: 1,
          steps: _steps,
        ),
        const SizedBox(height: 24),
        // Photos section
        _buildImagesSectionCard(),
        const SizedBox(height: 20),
        // Sizes section card
        _buildSizesSectionCard(),
        const SizedBox(height: 24),
        // Inline navigation buttons
        _buildStep2Actions(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildImagesSectionCard() {
    final totalImages = _imageUrls.length + _pendingImageFiles.length;
    return _formCard([
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Photos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          Text(
            '$totalImages uploaded (min 3)',
            style: TextStyle(
              fontSize: 11,
              color: totalImages >= 3
                  ? const Color(0xFF52C41A)
                  : const Color(0xFF8E8E93),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'High-quality photos help attract more customers.',
        style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
      ),
      const SizedBox(height: 12),
      // Image grid
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // Uploaded images
          ..._imageUrls.map((url) => _buildImageThumbnail(url)),
          // Pending upload images
          ..._pendingImageFiles.map((file) => _buildPendingImageThumbnail(file)),
          // Add button
          if (totalImages < 6)
            GestureDetector(
              onTap: _pickImages,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFFE8E8E8), width: 1.5),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 24, color: Color(0xFFBFBFBF)),
                    SizedBox(height: 2),
                    Text(
                      'Add',
                      style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFFBFBFBF),
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      if (totalImages < 3)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: Color(0xFFF57C00)),
                const SizedBox(width: 6),
                const Text(
                  'Upload at least 3 photos (US-15 requirement)',
                  style: TextStyle(fontSize: 11, color: Color(0xFF795548)),
                ),
              ],
            ),
          ),
        ),
    ]);
  }

  Widget _buildSizesSectionCard() {
    return _formCard([
      const Text(
        'Size Variants',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A1A),
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Add portion sizes (e.g. Small 250g, Medium 350g)',
        style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
      ),
      const SizedBox(height: 12),
      // Size list
      ..._sizes.asMap().entries.map((entry) {
        final idx = entry.key;
        final size = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE8E8E8)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          size.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        if (size.isPopular)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Popular',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFFF5222D),
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${size.weight.isNotEmpty ? '${size.weight} · ' : ''}Rs ${size.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8E8E93)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 18, color: Color(0xFF8E8E93)),
                onPressed: () => _editSize(idx),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFFF5222D)),
                onPressed: () => _removeSize(idx),
              ),
            ],
          ),
        );
      }),
      // Add size form
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildInlineTextField(
                    controller: _sizeNameCtrl,
                    hint: 'Name (e.g. Large)',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInlineTextField(
                    controller: _sizeWeightCtrl,
                    hint: 'Weight (e.g. 350g)',
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: _buildInlineTextField(
                    controller: _sizePriceCtrl,
                    hint: 'Price',
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      child: Checkbox(
                        value: _sizeIsPopular,
                        onChanged: (v) =>
                            setState(() => _sizeIsPopular = v ?? false),
                        activeColor: const Color(0xFFF5222D),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const Text('Popular',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addSize,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    _editingSizeIndex != null ? 'Update Size' : 'Add Size',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildStep2Actions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: () => _goToStep(0),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Color(0xFFD9D9D9)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text(
                'Go Back',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: () => _goToStep(2),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5222D),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shadowColor: const Color(0x0C000000),
              ),
              child: const Text(
                'Continue to Nutrition',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  //  Step 3 — Nutrition & Details
  // ──────────────────────────────────────────────

  Widget _buildStep3NutritionAndDetails() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        // Header row: back button + icon
        Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x1A000000),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.arrow_back,
                  color: Color(0xFF1A1A1A),
                  size: 20,
                ),
              ),
            ),
            const Text(
              'Add Menu',
              style: TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                height: 1.33,
              ),
            ),
            const Spacer(),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 8),
        // Title
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Nutrition & Details',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.33,
            ),
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(
          width: double.infinity,
          child: Text(
            'Step 3 of 3: Add nutritional info and final details.',
            style: TextStyle(
              color: Color(0xFF595959),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              height: 1.43,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Progress indicator
        const StepProgressIndicator(
          currentStep: 2,
          steps: _steps,
        ),
        const SizedBox(height: 24),
        // Nutrition card
        _formCard([
          const Text(
            'Nutrition Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Helps customers make informed choices',
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stepFieldLabel('Calories (kcal)'),
                    const SizedBox(height: 4),
                    _buildStepTextField(
                      controller: _caloriesCtrl,
                      hint: 'e.g. 450',
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stepFieldLabel('Portion Weight'),
                    const SizedBox(height: 4),
                    _buildStepTextField(
                      controller: _portionWeightCtrl,
                      hint: 'e.g. 350g',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 20),
        // Ingredients card
        _formCard([
          const Text(
            'Ingredients',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          if (_ingredients.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _ingredients.asMap().entries.map((entry) {
                return Chip(
                  label: Text(entry.value,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF1A1A1A))),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeIngredient(entry.key),
                  backgroundColor: const Color(0xFFF5F5F5),
                  side: BorderSide.none,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          if (_ingredients.isNotEmpty) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildInlineTextField(
                  controller: _ingredientCtrl,
                  hint: 'Add ingredient...',
                  onSubmitted: (_) => _addIngredient(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addIngredient,
                icon: const Icon(Icons.add_circle_outline,
                    color: Color(0xFFF5222D)),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 20),
        // Allergens card
        _formCard([
          const Text(
            'Allergens',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          if (_allergens.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _allergens.asMap().entries.map((entry) {
                return Chip(
                  label: Text(entry.value,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFF5222D))),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeAllergen(entry.key),
                  backgroundColor: const Color(0xFFFFF1F0),
                  side: BorderSide.none,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          if (_allergens.isNotEmpty) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildInlineTextField(
                  controller: _allergenCtrl,
                  hint: 'e.g. Milk, Eggs, Peanuts...',
                  onSubmitted: (_) => _addAllergen(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addAllergen,
                icon: const Icon(Icons.add_circle_outline,
                    color: Color(0xFFF5222D)),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 20),
        // Prep Time card
        _formCard([
          const Text(
            'Preparation Time',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          _stepFieldLabel('Prep Time (minutes)'),
          const SizedBox(height: 4),
          _buildStepTextField(
            controller: _prepTimeCtrl,
            hint: 'e.g. 15',
            keyboardType: TextInputType.number,
          ),
        ]),
        const SizedBox(height: 20),
        // Availability toggle
        _buildAvailabilityToggle(),
        // Delete button (edit mode only)
        if (widget.isEditing) ...[
          const SizedBox(height: 20),
          _buildDeleteButton(),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Toggle / Delete ─────────────────────────

  Widget _buildAvailabilityToggle() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              size: 20, color: Color(0xFF595959)),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Available for ordering',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
          Switch(
            value: _isAvailable,
            activeThumbColor: const Color(0xFFF5222D),
            activeTrackColor:
                const Color(0xFFF5222D).withValues(alpha: 0.5),
            onChanged: (v) => setState(() => _isAvailable = v),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirmDelete(),
        icon: const Icon(Icons.delete_outline, size: 18),
        label: const Text('Delete Item'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFF5222D),
          side: const BorderSide(color: Color(0xFFF5222D)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(
            'Are you sure you want to delete "${widget.existingItem!.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFF5222D))),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.deleteMenuItem(itemId: widget.existingItem!.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item deleted.'),
            backgroundColor: Color(0xFF52C41A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Bottom Action Bar ───────────────────────

  Widget _buildBottomBar() {
    if (_currentStep == 0) {
      // Continue button
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(width: 1, color: Colors.white),
          ),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () => _goToStep(1),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF5222D),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE0E0E0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Continue to Media & Sizes',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    // Step 3 — Save / Submit
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(width: 1, color: Colors.white),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Go Back button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: () => _goToStep(1),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Color(0xFFD9D9D9)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text(
                'Go Back to Media & Sizes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Save button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5222D),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                shadowColor: const Color(0x0C000000),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.isEditing ? 'Update Item' : 'Create Item',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared widgets ──────────────────────────

  Widget _formCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFE8E8E8)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _stepFieldLabel(String label) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF262626),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.50,
        ),
      ),
    );
  }

  Widget _buildStepTextField({
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: maxLines > 1 ? null : 48,
          width: double.infinity,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: hasError ? const Color(0xFFFFF1F0) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasError
                    ? const Color(0xFFF5222D)
                    : const Color(0xFFE8E8E8),
                width: hasError ? 1.5 : 1,
              ),
            ),
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              keyboardType: keyboardType,
              onChanged: onChanged,
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFFBFBFBF),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText,
              style: const TextStyle(
                color: Color(0xFFF5222D),
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInlineTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFBFBFBF)),
        ),
        isDense: true,
      ),
    );
  }

  // ── Thumbnail helpers ────────────────────────

  Widget _buildThumbnail({
    required ImageProvider imageProvider,
    required VoidCallback onRemove,
    String? badge,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(
            image: imageProvider,
            width: 80,
            height: 80,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 80,
              height: 80,
              color: const Color(0xFFF0F0F0),
              child: const Icon(Icons.broken_image,
                  color: Color(0xFFBFBFBF), size: 28),
            ),
          ),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Color(0xFFF5222D),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        if (badge != null)
          Positioned(
            bottom: 2,
            right: 2,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                badge,
                style: const TextStyle(color: Colors.white, fontSize: 8),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageThumbnail(String url) {
    return _buildThumbnail(
      imageProvider: NetworkImage(url),
      onRemove: () => setState(() => _imageUrls.remove(url)),
    );
  }

  Widget _buildPendingImageThumbnail(File file) {
    return _buildThumbnail(
      imageProvider: FileImage(file),
      onRemove: () => setState(() => _pendingImageFiles.remove(file)),
      badge: 'pending',
    );
  }
}
